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

import 'camera_capture_native.dart';

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

/// How many frames per second get *captured* (how finely a moving pen
/// stroke is timestamped/deduped while recording) versus how many end up
/// in the *final encoded video* (`-r`/`fps=` at encode time) -- these are
/// two genuinely separate concerns that don't have to share one number.
/// A long whiteboard recording is mostly static holds punctuated by short
/// bursts of actual drawing; since [MathPadRecordingService._captureFrame]
/// already collapses an unchanged board into one growing `duration` value
/// instead of real duplicate frames, encoding still re-expands every
/// second of that duration into real frames at whatever the *encode* rate
/// is -- so the encode rate, not the capture rate, is what actually drives
/// final file size and encode time. The tutor's choice is persisted
/// locally (see [MathPadRecordingService.loadFrameRateMode]/
/// `setFrameRateMode`) so it survives across sessions.
enum RecordingFrameRateMode {
  /// 60fps capture AND 60fps final video.
  /// Benefit: the smoothest possible motion for a fast-moving pen stroke,
  /// at both the sampling and playback stage.
  /// Cost: the largest files and slowest encode of the three -- a mostly-
  /// static 3-minute recording still gets ~10,800 real video frames baked
  /// in, most of them near-duplicates of the frame before.
  smooth60,

  /// 30fps capture AND 30fps final video.
  /// Benefit: roughly halves both file size and encode time versus
  /// [smooth60] -- fewer frames captured, fewer frames encoded.
  /// Cost: the only option where a fast stroke is also *sampled* coarser
  /// (33ms between capture attempts instead of 16.7ms), not just played
  /// back at a lower rate -- the small extra loss [balanced] avoids.
  compact30,

  /// 60fps capture, but only 30fps in the final encoded video.
  /// Benefit: the same file-size/encode-time win as [compact30] (final
  /// size is driven by the *encode* rate, not the capture rate), with
  /// none of its downside -- a fast stroke is still sampled at the full
  /// 60fps, ffmpeg just picks/downsamples from that finer source data
  /// when producing the 30fps output, instead of never having captured
  /// the in-between positions at all.
  /// Cost: essentially none for this kind of content -- 24-30fps is the
  /// normal rate for screen-recorded tutorials generally; 60fps video
  /// was headroom this content never needed. The recommended default.
  balanced,
}

/// The narration audio's final AAC bitrate -- a single spoken voice needs
/// nowhere near what music does, so this is one of the cheapest levers on
/// total file size: for a 3-minute recording, the difference between the
/// lowest and highest option here alone is roughly 2MB, on top of
/// whatever the video track adds. The tutor's choice is persisted locally
/// (see [MathPadRecordingService.loadAudioBitrateMode]/
/// `setAudioBitrateMode`) so it survives across sessions.
enum RecordingAudioBitrate {
  /// 96kbps.
  /// Benefit: smallest audio track -- roughly half the size of [high] for
  /// the same recording. Clean single-speaker narration is essentially
  /// transparent at this rate (comparable to what most podcasts/
  /// audiobooks ship at); `dynaudnorm` is already smoothing the signal
  /// before this bitrate is even applied.
  /// Cost: essentially none for narration; would start to show on music
  /// or complex/noisy audio, but that's not what this records.
  /// Recommended default.
  compact,

  /// 128kbps.
  /// Benefit: a bit more headroom than [compact] for a noisier room or a
  /// mic picking up more background sound, at a modest size cost.
  /// Cost: roughly a third larger than [compact] for the same recording.
  standard,

  /// 192kbps -- the original, unconditional rate this used before this
  /// setting existed.
  /// Benefit: maximum quality margin, no perceptible difference from
  /// [standard] for narration in practice.
  /// Cost: the largest audio track of the three, for a difference most
  /// tutors won't be able to hear on spoken narration.
  high,
}

/// How the camera stream gets timed against the canvas/audio when
/// [MathPadRecordingService.start] is called with `includeCamera: true`.
/// The tutor's choice is persisted locally (see
/// [MathPadRecordingService.loadCameraSyncMethod]/`setCameraSyncMethod`)
/// so it survives across sessions.
enum CameraSyncMethod {
  /// Camera capture runs as an independent `ffmpeg` process, same as the
  /// canvas/audio's own encode pipeline. Its start latency is measured by
  /// watching for the first `frame=` line in ffmpeg's own stderr status
  /// output (see `start()`) -- accurate to within roughly the interval
  /// ffmpeg prints that line at (tightened to 100ms via `-stats_period`).
  /// Benefit: no extra native dependency, proven, works the same on every
  /// webcam/driver ffmpeg's DirectShow backend already supports.
  /// Cost: bounded to roughly a 100ms residual, not exact.
  /// Recommended default.
  ffmpegEstimate,

  /// Camera capture runs through a small native Media Foundation module
  /// (`jyamiti_camera.dll`, see `windows/native_camera/camera_capture.cpp`)
  /// that captures AND encodes the webcam itself, reading the real system
  /// clock at the exact instant the first frame is delivered by the
  /// driver -- a genuine, sub-millisecond-accurate timestamp instead of an
  /// estimate.
  /// Benefit: the camera is aligned to the canvas/audio as exactly as this
  /// app can achieve.
  /// Cost: real testing found Media Foundation and ffmpeg's DirectShow
  /// capture cannot reliably share one physical camera at once, so this
  /// mode replaces ffmpeg for the camera stream entirely rather than just
  /// supplementing it -- a genuinely different code path (its own
  /// encoder negotiation, its own error handling) with less real-world
  /// mileage than the ffmpeg path across the wide range of webcams/
  /// drivers tutors might have.
  nativePrecise,
}

/// Whether Windows' own microphone enhancements (noise suppression,
/// automatic gain control) are allowed to process the narration signal
/// before it's captured -- applies to BOTH audio capture paths (the
/// ffmpeg/`record`-package one via its `autoGain`/`noiseSuppress`
/// options, and the native WASAPI one via `AUDCLNT_STREAMOPTIONS_RAW`;
/// see `camera_capture_native.dart`/`audio_capture.cpp`). The tutor's
/// choice is persisted locally (see
/// [MathPadRecordingService.loadMicEnhancementMode]/
/// `setMicEnhancementMode`) so it survives across sessions.
enum MicEnhancementMode {
  /// Bypass Windows' enhancement chain -- as close to the mic's raw,
  /// unprocessed signal as this app can get.
  /// Benefit: avoids a real, confirmed failure mode -- Windows' noise
  /// suppression estimates a "noise floor" from what looks steady/
  /// unchanging, and can mistake a sustained, unvarying sound (a long
  /// held vowel, a held music note) for background noise and gate it
  /// out partway through, while normal varying speech is unaffected.
  /// Cost: none of Windows' own noise cleanup in a genuinely noisy room
  /// -- what you capture is what the mic actually picked up.
  /// Recommended default.
  disabled,

  /// Let Windows apply its own microphone enhancements as it normally
  /// would for any app.
  /// Benefit: can meaningfully clean up narration recorded in a noisy
  /// room (fan/AC hum, keyboard clatter, etc.) -- exactly what those
  /// enhancements are designed for.
  /// Cost: reintroduces the sustained-tone gating risk [disabled] avoids.
  enabled,
}

/// Whether a recording WITH a camera composites the picture-in-picture
/// overlay all at once at the very end ([finalPass]) or incrementally,
/// segment by segment, while still recording ([liveSegmented]) -- see
/// the class doc comment's "Real-time (background) segment encoding"
/// section for the underlying canvas-only sealing this builds on, and
/// the "Live segmented camera compositing" section for how the camera
/// side reuses that same infrastructure. The tutor's choice is
/// persisted locally (see
/// [MathPadRecordingService.loadCameraEncodeMode]/`setCameraEncodeMode`)
/// so it survives across sessions.
enum CameraEncodeMode {
  /// The camera overlay is composited in ONE pass covering the whole
  /// recording, only once `stop()` is called.
  /// Benefit: simplest, most-tested path -- the camera capture itself is
  /// just one continuous file, nothing to split or reassemble.
  /// Cost: none of a camera recording's overlay work can happen ahead of
  /// time -- `encode()` has to decode the ENTIRE canvas timeline back to
  /// raw frames (even portions already sealed into finished segments)
  /// and re-encode the whole composited result from scratch, so a
  /// recording with a camera on can take noticeably longer to finish
  /// than the same recording without one.
  /// Recommended default.
  finalPass,

  /// The camera overlay is composited incrementally: each time a canvas
  /// segment seals (see `_evaluateSegmentSeal`), its matching slice of
  /// camera footage gets composited into that segment right then, in
  /// the background, while recording continues -- located using the
  /// SAME single, fixed camera-start offset the tutor's chosen
  /// `CameraSyncMethod` already measures once, so there's nothing new to
  /// re-estimate or drift across segments the way an earlier, reverted
  /// version of this idea did.
  /// Benefit: `stop()`/`encode()` only has real overlay+encode work left
  /// for the short uncommitted tail -- everything already sealed just
  /// gets stream-copy-concatenated, the same speed win the camera-less
  /// path already enjoys.
  /// Cost: a newer, less-tested path than [finalPass].
  liveSegmented,

  /// The camera never gets captured as a separate stream at all -- a live
  /// camera preview is rendered directly inside Math Pad's own canvas
  /// capture area (see `mathpad.dart`'s capture-area `Stack`), so every
  /// captured canvas frame already has the camera baked in by the time
  /// it's captured. This is how professional recording software (OBS,
  /// Zoom, Loom, etc.) actually does picture-in-picture -- compositing
  /// live, per frame, into ONE stream, rather than capturing two separate
  /// streams and reconciling them afterward the way both other options
  /// here do. `start()` doesn't spawn any camera process or native
  /// capture for this mode -- there's no camera.mp4, no offset to
  /// measure, and no overlay pass of any kind; `encode()` already takes
  /// its fast camera-less path automatically whenever no camera.mp4
  /// exists.
  /// Benefit: encoding finishes exactly as fast as a camera-less
  /// recording, always -- by construction, not by approximation. Also
  /// sidesteps every class of problem the other two options exist to
  /// solve (sync offset measurement, segment-splice artifacts) simply by
  /// never creating two streams that need reconciling in the first
  /// place.
  /// Cost: the frame-dedup optimization that skips writing a new frame
  /// while the board sits idle (see the class doc comment) stops helping
  /// for as long as the camera preview is live and visibly changing -- a
  /// real camera feed is essentially never pixel-identical frame to
  /// frame, so a paused/idle stretch with the camera on writes many more
  /// frames to disk than the same stretch would with either other
  /// option. Also renders the camera preview live on the tutor's own
  /// screen while recording (the other two modes never show it until
  /// playback) -- a real, deliberate behaviour change, not a bug. Best
  /// suited to a higher-performance machine that can absorb the extra
  /// live capture/encode cost throughout the recording in exchange for
  /// an instant finish.
  onCanvas,

  /// The real fix for [onCanvas]'s one real cost: a native module
  /// (`external_compositor.cpp`) captures this app's own window via the
  /// Windows Graphics Capture API (the same mechanism OBS's modern
  /// window-capture source uses -- content DWM has ALREADY composited
  /// for display, no extra work asked of Flutter itself), optionally
  /// composites a live camera feed on top (Direct2D), and encodes the
  /// result (a continuously-running, piped ffmpeg process) -- all in a
  /// separate native process/thread, entirely outside Flutter's own
  /// rendering pipeline. `start()` doesn't drive Flutter's normal frame
  /// capture AT ALL for this mode (no `_captureFrame`, no PNG files, no
  /// segment-sealing, `recordingPipelineMode` is ignored) -- the native
  /// module handles literally all of the video side by itself; only
  /// audio still records the normal way, muxed in once encoding stops.
  /// Benefit: `onCanvas`'s live-camera-preview idea WITHOUT its
  /// drawing-lag cost, confirmed via real testing -- compositing and
  /// encoding genuinely never touch Flutter's UI/raster thread, so
  /// drawing stays exactly as smooth as a plain recording. Also finishes
  /// essentially instantly, same as [onCanvas].
  /// Cost: a newer, least-tested path of the four -- and captures this
  /// app's FULL top-level window (whatever WGC sees on screen), not
  /// precisely cropped to just the canvas capture area the other three
  /// options use, so the recording may include surrounding UI chrome
  /// the others wouldn't.
  externalCompositor,
}

/// How captured canvas frames get turned into the final video --
/// [snapshotBased] (the existing approach, unchanged, everything else in
/// this class is built around) writes each captured frame as a PNG file
/// and assembles them afterward via ffmpeg's concat demuxer (optionally
/// with background segment-sealing -- see [SegmentSealMode]);
/// [continuousStream] instead pipes each captured frame's raw pixels
/// directly into ONE continuously-running ffmpeg encoder process for the
/// whole recording -- the same fundamental technique professional
/// recording software actually uses. [CameraEncodeMode.onCanvas]'s doc
/// comment covers the "how big companies actually COMPOSITE" half of
/// that; this is the "how they actually ENCODE" half. The tutor's choice
/// is persisted locally (see
/// [MathPadRecordingService.loadRecordingPipelineMode]/
/// `setRecordingPipelineMode`) so it survives across sessions.
enum RecordingPipelineMode {
  /// Every frame is written to disk as an individual PNG file, later
  /// assembled into video via ffmpeg.
  /// Benefit: the original, most-tested path every other setting in this
  /// class was built and verified against.
  /// Cost: real disk I/O and PNG-encode work per captured frame, plus an
  /// assembly step even in the fast (segments-already-sealed) case.
  /// Recommended default.
  snapshotBased,

  /// Each captured frame's raw pixels are piped directly into one
  /// continuously-running ffmpeg process that encodes them in real time
  /// for the whole recording -- no PNG files, no segment-sealing, no
  /// assembly step. `stop()` just closes the pipe; the video is already
  /// fully encoded by the time it does, so `encode()` only has a quick
  /// audio mux left, not a real video encode.
  /// Benefit: finishes essentially instantly regardless of recording
  /// length, and skips the disk I/O + PNG-encode cost of the
  /// snapshot-based path entirely.
  /// Cost: a newer, less-tested path. Requires a FIXED capture-area
  /// pixel size for the whole recording -- a raw-video pipe can't change
  /// dimensions mid-stream the way each independently-sized PNG can, so
  /// resizing the window mid-recording drops frames rather than adapting
  /// to the new size. Not compatible with
  /// `CameraEncodeMode.finalPass`/`liveSegmented` (both need the
  /// snapshot-based pipeline's assembly machinery to merge in a
  /// separately-captured camera stream) -- selecting either of those
  /// together with this silently falls back to `snapshotBased` for that
  /// recording; pair this with `CameraEncodeMode.onCanvas` (or no
  /// camera) instead.
  continuousStream,
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
    unawaited(loadFrameRateMode());
    unawaited(loadAudioBitrateMode());
    unawaited(loadCameraSyncMethod());
    unawaited(loadMicEnhancementMode());
    unawaited(loadCameraEncodeMode());
    unawaited(loadRecordingPipelineMode());
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

  /// Loads the tutor's saved [frameRateMode] from local storage, if any
  /// was ever saved -- falls back to (and leaves unchanged) whatever
  /// [frameRateMode] already is on any error or missing value.
  Future<void> loadFrameRateMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? saved = prefs.getString(_kFrameRateModePrefKey);
      if (saved == null) return;
      frameRateMode = RecordingFrameRateMode.values.firstWhere(
        (m) => m.name == saved,
        orElse: () => frameRateMode,
      );
      notifyListeners();
    } catch (_) {
      // Keep whatever `frameRateMode` already was.
    }
  }

  /// Changes [frameRateMode] and persists the choice locally so it's still
  /// in effect the next time the app opens. The actual capture/encode fps
  /// values for a given recording are snapshotted once, in `start()` --
  /// changing this mid-recording (the settings UI disables that anyway)
  /// wouldn't retroactively apply to one already running.
  Future<void> setFrameRateMode(RecordingFrameRateMode mode) async {
    frameRateMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kFrameRateModePrefKey, mode.name);
    } catch (_) {
      // Setting still applies for the rest of this session even if saving
      // it for next time happened to fail.
    }
  }

  /// Loads the tutor's saved [audioBitrateMode] from local storage, if any
  /// was ever saved -- falls back to (and leaves unchanged) whatever
  /// [audioBitrateMode] already is on any error or missing value.
  Future<void> loadAudioBitrateMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? saved = prefs.getString(_kAudioBitrateModePrefKey);
      if (saved == null) return;
      audioBitrateMode = RecordingAudioBitrate.values.firstWhere(
        (m) => m.name == saved,
        orElse: () => audioBitrateMode,
      );
      notifyListeners();
    } catch (_) {
      // Keep whatever `audioBitrateMode` already was.
    }
  }

  /// Changes [audioBitrateMode] and persists the choice locally so it's
  /// still in effect the next time the app opens. Only read at `encode()`
  /// time (see `_capturedAudioBitrateKbps`) -- capture itself always
  /// records raw WAV regardless of this setting, so changing it never
  /// affects an already-running recording, only how its narration gets
  /// compressed once encoding actually happens.
  Future<void> setAudioBitrateMode(RecordingAudioBitrate mode) async {
    audioBitrateMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kAudioBitrateModePrefKey, mode.name);
    } catch (_) {
      // Setting still applies for the rest of this session even if saving
      // it for next time happened to fail.
    }
  }

  /// Loads the tutor's saved [cameraSyncMethod] from local storage, if any
  /// was ever saved -- falls back to (and leaves unchanged) whatever
  /// [cameraSyncMethod] already is on any error or missing value.
  Future<void> loadCameraSyncMethod() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? saved = prefs.getString(_kCameraSyncMethodPrefKey);
      if (saved == null) return;
      cameraSyncMethod = CameraSyncMethod.values.firstWhere(
        (m) => m.name == saved,
        orElse: () => cameraSyncMethod,
      );
      notifyListeners();
    } catch (_) {
      // Keep whatever `cameraSyncMethod` already was.
    }
  }

  /// Changes [cameraSyncMethod] and persists the choice locally so it's
  /// still in effect the next time the app opens. Only read at `start()`
  /// time, when a recording with `includeCamera: true` actually begins --
  /// changing it never affects a recording already in progress.
  Future<void> setCameraSyncMethod(CameraSyncMethod method) async {
    cameraSyncMethod = method;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCameraSyncMethodPrefKey, method.name);
    } catch (_) {
      // Setting still applies for the rest of this session even if saving
      // it for next time happened to fail.
    }
  }

  /// Loads the tutor's saved [micEnhancementMode] from local storage, if
  /// any was ever saved -- falls back to (and leaves unchanged) whatever
  /// [micEnhancementMode] already is on any error or missing value.
  Future<void> loadMicEnhancementMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? saved = prefs.getString(_kMicEnhancementModePrefKey);
      if (saved == null) return;
      micEnhancementMode = MicEnhancementMode.values.firstWhere(
        (m) => m.name == saved,
        orElse: () => micEnhancementMode,
      );
      notifyListeners();
    } catch (_) {
      // Keep whatever `micEnhancementMode` already was.
    }
  }

  /// Changes [micEnhancementMode] and persists the choice locally so
  /// it's still in effect the next time the app opens. Only read at
  /// `start()` time -- changing it never affects a recording already in
  /// progress.
  Future<void> setMicEnhancementMode(MicEnhancementMode mode) async {
    micEnhancementMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kMicEnhancementModePrefKey, mode.name);
    } catch (_) {
      // Setting still applies for the rest of this session even if saving
      // it for next time happened to fail.
    }
  }

  /// Loads the tutor's saved [cameraEncodeMode] from local storage, if
  /// any was ever saved -- falls back to (and leaves unchanged) whatever
  /// [cameraEncodeMode] already is on any error or missing value.
  Future<void> loadCameraEncodeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? saved = prefs.getString(_kCameraEncodeModePrefKey);
      if (saved == null) return;
      cameraEncodeMode = CameraEncodeMode.values.firstWhere(
        (m) => m.name == saved,
        orElse: () => cameraEncodeMode,
      );
      notifyListeners();
    } catch (_) {
      // Keep whatever `cameraEncodeMode` already was.
    }
  }

  /// Changes [cameraEncodeMode] and persists the choice locally so it's
  /// still in effect the next time the app opens. Only read at
  /// `start()` time -- changing it never affects a recording already in
  /// progress.
  Future<void> setCameraEncodeMode(CameraEncodeMode mode) async {
    cameraEncodeMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCameraEncodeModePrefKey, mode.name);
    } catch (_) {
      // Setting still applies for the rest of this session even if saving
      // it for next time happened to fail.
    }
  }

  /// Loads the tutor's saved [recordingPipelineMode] from local storage,
  /// if any was ever saved -- falls back to (and leaves unchanged)
  /// whatever [recordingPipelineMode] already is on any error or missing
  /// value.
  Future<void> loadRecordingPipelineMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? saved = prefs.getString(_kRecordingPipelineModePrefKey);
      if (saved == null) return;
      recordingPipelineMode = RecordingPipelineMode.values.firstWhere(
        (m) => m.name == saved,
        orElse: () => recordingPipelineMode,
      );
      notifyListeners();
    } catch (_) {
      // Keep whatever `recordingPipelineMode` already was.
    }
  }

  /// Changes [recordingPipelineMode] and persists the choice locally so
  /// it's still in effect the next time the app opens. Only read at
  /// `start()` time -- changing it never affects a recording already in
  /// progress.
  Future<void> setRecordingPipelineMode(RecordingPipelineMode mode) async {
    recordingPipelineMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kRecordingPipelineModePrefKey, mode.name);
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
  // desyncing from the audio track. This is the CEILING -- the actual
  // per-recording capture/encode rates are chosen from [frameRateMode]
  // (see `_activeCaptureFps`/`_activeEncodeFps`, set in `start()`), not a
  // single fixed constant any more.
  static const int _kMaxFps = 60;
  static const int _kCompactFps = 30;

  /// The tutor's chosen frame-rate strategy -- defaults to
  /// [RecordingFrameRateMode.balanced] until [loadFrameRateMode] (fired
  /// from the constructor, best-effort) resolves whatever was actually
  /// saved locally.
  RecordingFrameRateMode frameRateMode = RecordingFrameRateMode.balanced;
  static const String _kFrameRateModePrefKey = 'mathpad_recording_framerate_mode';

  int _captureFpsFor(RecordingFrameRateMode mode) => switch (mode) {
    RecordingFrameRateMode.smooth60 => _kMaxFps,
    RecordingFrameRateMode.compact30 => _kCompactFps,
    RecordingFrameRateMode.balanced => _kMaxFps,
  };

  int _encodeFpsFor(RecordingFrameRateMode mode) => switch (mode) {
    RecordingFrameRateMode.smooth60 => _kMaxFps,
    RecordingFrameRateMode.compact30 => _kCompactFps,
    RecordingFrameRateMode.balanced => _kCompactFps,
  };

  // Snapshotted once in `start()` from `frameRateMode` -- capture cadence
  // (`_activeCaptureFps`) and the final encoded video's frame rate
  // (`_activeEncodeFps`, carried through to `_capturedEncodeFps` for the
  // deferred `encode()` step) deliberately don't have to match; see
  // `RecordingFrameRateMode`'s doc comment for why. Default to
  // `balanced`'s values until a real recording sets them.
  int _activeCaptureFps = _kMaxFps;
  int _activeEncodeFps = _kCompactFps;
  int _capturedEncodeFps = _kCompactFps;

  /// The tutor's chosen narration audio bitrate -- defaults to
  /// [RecordingAudioBitrate.compact] until [loadAudioBitrateMode] (fired
  /// from the constructor, best-effort) resolves whatever was actually
  /// saved locally.
  RecordingAudioBitrate audioBitrateMode = RecordingAudioBitrate.compact;
  static const String _kAudioBitrateModePrefKey =
      'mathpad_recording_audio_bitrate';

  int _audioKbpsFor(RecordingAudioBitrate mode) => switch (mode) {
    RecordingAudioBitrate.compact => 96,
    RecordingAudioBitrate.standard => 128,
    RecordingAudioBitrate.high => 192,
  };

  /// The tutor's chosen camera sync method -- defaults to
  /// [CameraSyncMethod.ffmpegEstimate] until [loadCameraSyncMethod]
  /// (fired from the constructor, best-effort) resolves whatever was
  /// actually saved locally.
  CameraSyncMethod cameraSyncMethod = CameraSyncMethod.ffmpegEstimate;
  static const String _kCameraSyncMethodPrefKey =
      'mathpad_recording_camera_sync_method';

  /// The tutor's chosen microphone-enhancement policy -- defaults to
  /// [MicEnhancementMode.disabled] until [loadMicEnhancementMode] (fired
  /// from the constructor, best-effort) resolves whatever was actually
  /// saved locally.
  MicEnhancementMode micEnhancementMode = MicEnhancementMode.disabled;
  static const String _kMicEnhancementModePrefKey =
      'mathpad_recording_mic_enhancement_mode';

  /// The tutor's chosen camera overlay compositing strategy -- defaults
  /// to [CameraEncodeMode.finalPass] until [loadCameraEncodeMode] (fired
  /// from the constructor, best-effort) resolves whatever was actually
  /// saved locally.
  CameraEncodeMode cameraEncodeMode = CameraEncodeMode.finalPass;
  static const String _kCameraEncodeModePrefKey =
      'mathpad_recording_camera_encode_mode';

  /// The tutor's chosen recording pipeline -- defaults to
  /// [RecordingPipelineMode.snapshotBased] until [loadRecordingPipelineMode]
  /// (fired from the constructor, best-effort) resolves whatever was
  /// actually saved locally.
  RecordingPipelineMode recordingPipelineMode = RecordingPipelineMode.snapshotBased;
  static const String _kRecordingPipelineModePrefKey =
      'mathpad_recording_pipeline_mode';

  // Snapshotted in `stopCapture()` from `audioBitrateMode` -- capture
  // itself always records raw WAV regardless of this setting (it's only
  // ever read at `encode()` time), but frozen the same way as the other
  // `_captured*` fields for consistency with how `encode()` sources
  // everything else it needs.
  int _capturedAudioBitrateKbps = 96;

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
  // Always 0 by construction now -- `start()` waits for the camera to
  // confirm it's actually producing frames BEFORE `_startedAt` is even
  // set, so there's no start-of-recording lag left for `encode()` to
  // correct for here. Kept as a field (rather than deleted outright) since
  // `encode()` still reads it generically alongside `_audioStartOffsetSeconds`.
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
  // Cumulative canvas-timeline seconds represented by every segment
  // sealed so far -- i.e. where, on the shared `_startedAt`-anchored
  // timeline, the NEXT segment (or the leftover tail) actually starts.
  // Only meaningful for/updated by `CameraEncodeMode.liveSegmented` (see
  // `_maybeSealSegment`), but harmless to track unconditionally.
  double _sealedTimelineSeconds = 0.0;
  double _capturedSealedTimelineSeconds = 0.0;
  // Snapshotted once in `start()` from `cameraEncodeMode` -- same
  // reasoning as `_activeCaptureFps`/`_activeEncodeFps`: a live setting
  // change mid-recording must never produce a mix of segments sealed
  // under two different strategies.
  CameraEncodeMode _activeCameraEncodeMode = CameraEncodeMode.finalPass;
  CameraEncodeMode _capturedActiveCameraEncodeMode = CameraEncodeMode.finalPass;
  // Snapshotted once in `start()` from its own `includeCamera` argument --
  // lets [isOnCanvasCameraActive] tell whether THIS recording asked for a
  // camera at all, since `CameraEncodeMode.onCanvas` never sets
  // `_cameraEnabled` (there's no separate camera stream for it to enable).
  bool _activeIncludeCamera = false;

  /// True while a recording is active, asked for a camera, and
  /// [CameraEncodeMode.onCanvas] is selected -- the UI (see
  /// `mathpad.dart`'s capture-area `Stack`) watches this to know when to
  /// show its own live camera preview inside the capture area. Nothing in
  /// this service manages that preview or its `CameraController` -- see
  /// [CameraEncodeMode.onCanvas]'s doc comment for the full split of
  /// responsibility.
  bool get isOnCanvasCameraActive =>
      _state == MathPadRecordingState.recording &&
      _activeIncludeCamera &&
      _activeCameraEncodeMode == CameraEncodeMode.onCanvas;

  // ─── `RecordingPipelineMode.continuousStream` state -- entirely
  // separate from every field above; the snapshot-based path (`_frameCount`,
  // `_concatEntries`, `_lastFrameBytes`, segment-sealing, ...) is never
  // touched by this mode, and vice versa. See `_captureFrameContinuousStream`
  // and `RecordingPipelineMode.continuousStream`'s doc comment. ───────────
  // Snapshotted once in `start()`, same reasoning as the other `_active*`
  // fields -- also where the `finalPass`/`liveSegmented` camera
  // incompatibility fallback (see the enum's doc comment) actually gets
  // decided.
  RecordingPipelineMode _activeRecordingPipelineMode = RecordingPipelineMode.snapshotBased;
  Process? _continuousStreamProcess;
  bool _continuousStreamProcessExited = false;
  int _continuousStreamWidth = 0;
  int _continuousStreamHeight = 0;
  String? _continuousStreamOutputPath;
  // The last successfully captured frame's raw RGBA bytes -- re-written
  // to the pipe (cheaply) for any due tick where nothing changed on the
  // board, since a raw stream (unlike the snapshot path's PNG+duration
  // entries) has no way to say "hold this frame N ticks longer".
  Uint8List? _lastContinuousStreamFrameBytes;
  int _continuousStreamFrameCount = 0;
  bool _continuousStreamCaptureInFlight = false;
  String? _capturedContinuousStreamOutputPath;
  double _capturedContinuousStreamDurationSeconds = 0.0;
  RecordingPipelineMode _capturedActiveRecordingPipelineMode =
      RecordingPipelineMode.snapshotBased;

  // ─── Camera capture (optional, additive -- see the class doc above) ────
  // Entirely separate from everything above: its own ffmpeg process
  // writing its own file, started/stopped alongside the canvas
  // capture/mic but never read from or written into by any of it.
  Process? _cameraProcess;
  bool _cameraEnabled = false;
  // Set instead of `_cameraProcess` when `cameraSyncMethod` is
  // [CameraSyncMethod.nativePrecise] -- see that enum value's doc comment
  // and `camera_capture_native.dart`. Never both at once for the same
  // recording.
  NativeCameraCapture? _nativeCamera;
  // Set instead of using `_audioRecorder` for capture when
  // `cameraSyncMethod` is [CameraSyncMethod.nativePrecise] -- unlike
  // `_nativeCamera` this applies to EVERY recording in that mode, not
  // just ones with `includeCamera: true` (audio-vs-canvas sync matters
  // regardless of whether a camera is involved at all).
  NativeAudioCapture? _nativeAudio;
  // Set instead of the separate-camera-stream AND Flutter-side capture
  // machinery entirely when `cameraEncodeMode` is
  // [CameraEncodeMode.externalCompositor] -- see that enum value's doc
  // comment. Handles the whole video side (window capture, optional
  // camera overlay, encode) by itself; audio still records the normal
  // way alongside it and gets muxed in once this stops.
  NativeExternalCompositor? _externalCompositor;
  String? _capturedExternalCompositorOutputPath;
  double _capturedExternalCompositorDurationSeconds = 0.0;

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
      await process.stdin.close();
    } catch (_) {}
    try {
      await process.exitCode.timeout(const Duration(seconds: 5));
    } catch (_) {
      process.kill(ProcessSignal.sigkill);
    }
  }

  /// Stops+finalizes the native camera capture (if one was started) and
  /// releases its native resources -- the native-module equivalent of
  /// [_stopCameraCapture]. Runs synchronously: the underlying FFI call
  /// blocks until the worker thread joins and the MP4 is finalized, which
  /// real-hardware testing found fast (finalize completed effectively
  /// immediately after the capture loop ended) -- comfortably within
  /// what the ffmpeg path's own stop already allows for. If that ever
  /// proves visibly janky in practice, moving it onto `Isolate.run`
  /// (passing just the raw handle int across, since FFI-bound closures
  /// can't cross isolates) is the fix.
  ///
  /// Unlike `_cameraProcess`, a hard-kill of the app can never orphan
  /// this and leave the webcam locked -- there's no separate process to
  /// orphan, the capture thread lives and dies with `jyamiti.exe` itself
  /// (see the "Windows Job Object" section's doc comment for why that
  /// concern exists for the ffmpeg path at all).
  void _stopNativeCameraCapture() {
    final NativeCameraCapture? camera = _nativeCamera;
    _nativeCamera = null;
    if (camera == null) return;
    camera.stop();
    camera.dispose();
  }

  /// Polls [camera] for its real captured first-frame wall-clock
  /// timestamp and folds it into `_cameraStartOffsetSeconds` once
  /// available -- see [CameraSyncMethod.nativePrecise]'s doc comment and
  /// where this is kicked off (unawaited) in `start()`. Bounded the same
  /// way the ffmpeg path bounds its own wait: a camera that never
  /// produces a frame at all just leaves the offset at its 0.0 default
  /// (equivalent to the ffmpeg path's own timeout fallback) rather than
  /// polling forever.
  Future<void> _resolveNativeCameraOffset(
    NativeCameraCapture camera,
    DateTime startedAt,
  ) async {
    const Duration pollInterval = Duration(milliseconds: 15);
    const Duration giveUpAfter = Duration(seconds: 8);
    final DateTime deadline = DateTime.now().add(giveUpAfter);
    while (DateTime.now().isBefore(deadline)) {
      // `_nativeCamera` can be reassigned/cleared by a later `start()`
      // call (or cleared by `stop()`/`cancel()`) while this loop is still
      // running for a PREVIOUS recording -- bail out rather than writing
      // a stale offset into whatever's current now.
      if (!identical(_nativeCamera, camera)) return;
      if (camera.isFirstFrameReady) {
        final DateTime cameraFirstFrameAt =
            DateTime.fromMicrosecondsSinceEpoch(camera.firstFrameUnixMicros);
        _cameraStartOffsetSeconds = max(
          0.0,
          cameraFirstFrameAt.difference(startedAt).inMicroseconds / 1e6,
        );
        return;
      }
      await Future<void>.delayed(pollInterval);
    }
    onCameraWarning?.call(
      'Camera is taking a while to start -- continuing without waiting further.',
    );
  }

  /// Audio-side equivalent of [_resolveNativeCameraOffset] -- polls
  /// [audio] for its real captured first-packet wall-clock timestamp and
  /// folds it into `_audioStartOffsetSeconds` once available. Same
  /// bounding/give-up reasoning applies; on timeout `_audioStartOffsetSeconds`
  /// just stays at its 0.0 default (no worse than the ffmpeg/`record`
  /// path's own estimate would be in the same situation).
  Future<void> _resolveNativeAudioOffset(
    NativeAudioCapture audio,
    DateTime startedAt,
  ) async {
    const Duration pollInterval = Duration(milliseconds: 15);
    const Duration giveUpAfter = Duration(seconds: 8);
    final DateTime deadline = DateTime.now().add(giveUpAfter);
    while (DateTime.now().isBefore(deadline)) {
      if (!identical(_nativeAudio, audio)) return;
      if (audio.isFirstFrameReady) {
        final DateTime audioFirstPacketAt =
            DateTime.fromMicrosecondsSinceEpoch(audio.firstFrameUnixMicros);
        _audioStartOffsetSeconds = max(
          0.0,
          audioFirstPacketAt.difference(startedAt).inMicroseconds / 1e6,
        );
        return;
      }
      await Future<void>.delayed(pollInterval);
    }
    // No `onCameraWarning`-style callback here deliberately -- audio is
    // never optional the way the camera is, so a slow-to-confirm mic
    // shouldn't nag the tutor with a warning; it just quietly keeps the
    // 0.0 default, same as it always did before this feature existed.
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

    // Camera goes FIRST now, before the video timeline's zero point even
    // exists -- it's consistently the slowest of the three capture streams
    // to actually come online (spawning the ffmpeg process is fast, but
    // DirectShow/AVFoundation then has to open the physical device, which
    // can visibly take anywhere from a few hundred ms to a couple of
    // seconds). Every earlier design here instead started everything at
    // once and tried to measure/correct for that lag afterward (spawn-time
    // estimates, live progress-line detection, ground-truth duration
    // probing, even a whole segment-based re-alignment scheme) -- all of
    // that was solving the wrong problem. Waiting HERE, before `_startedAt`
    // exists, means there's no lag left to correct for: by the time the
    // canvas/audio actually start, the camera is already confirmed to be
    // producing real frames.
    _cameraEnabled = false;
    _cameraProcess = null;
    _nativeCamera = null;
    _externalCompositor = null;
    // Neither `CameraEncodeMode.onCanvas` nor `.externalCompositor` ever
    // spawns a separate camera stream -- see their doc comments. Camera
    // compositing for `onCanvas` is handled entirely by the UI (via
    // `isOnCanvasCameraActive`); for `externalCompositor`, by the native
    // module itself (started further below) -- this whole block simply
    // has nothing to do for either mode.
    final bool includeSeparateCameraStream =
        includeCamera &&
        cameraEncodeMode != CameraEncodeMode.onCanvas &&
        cameraEncodeMode != CameraEncodeMode.externalCompositor;
    // Only the ffmpeg path exists on macOS -- the native module is a
    // Windows-only Media Foundation DLL (see `CameraSyncMethod`'s doc
    // comment), so macOS always behaves as if `ffmpegEstimate` were
    // chosen regardless of the saved setting.
    final bool useNativeCamera =
        includeSeparateCameraStream &&
        !Platform.isMacOS &&
        cameraSyncMethod == CameraSyncMethod.nativePrecise;
    if (includeSeparateCameraStream && useNativeCamera) {
      // Native Media Foundation path -- see `CameraSyncMethod.nativePrecise`'s
      // doc comment. Unlike the ffmpeg path below, this doesn't need to
      // wait for the camera before starting anything else: its offset
      // (computed just below, once `_startedAt` exists) comes from a real
      // captured wall-clock timestamp, not an estimate anchored to when
      // the timeline happened to start, so it stays exact no matter which
      // order things actually start in.
      try {
        final String? device = await _detectCameraDeviceName();
        if (device == null) {
          onCameraWarning?.call('No camera was found -- recording without one.');
        } else {
          _nativeCamera = NativeCameraCapture.start(
            device,
            p.join(sessionDir.path, 'camera.mp4'),
          );
          _cameraEnabled = true;
        }
      } catch (e) {
        _nativeCamera?.dispose();
        _nativeCamera = null;
        _cameraEnabled = false;
        onCameraWarning?.call('Could not start the camera -- recording without it.');
      }
    } else if (includeSeparateCameraStream) {
      try {
        final String? device = await _detectCameraDeviceName();
        final String ffmpegPath = _resolveFfmpegPath();
        if (device == null) {
          onCameraWarning?.call('No camera was found -- recording without one.');
        } else {
          // `-stats_period` tightens how often ffmpeg prints its `frame=`
          // stderr line (default 0.5s) down to 100ms -- the readiness wait
          // below fires on the FIRST such line, so this is what keeps that
          // detection close to the camera's true first frame instead of up
          // to half a second behind it.
          //
          // `-movflags frag_keyframe+empty_moov+default_base_moof` writes
          // a FRAGMENTED mp4 -- unlike a normal mp4 (whose index/`moov`
          // atom is only written once, at the very end, when the file is
          // closed), a fragmented one is valid and readable/sliceable at
          // any point WHILE still being written. Confirmed by direct
          // testing. Applied unconditionally (harmless for
          // `CameraEncodeMode.finalPass`, which never reads the file
          // until capture stops anyway) rather than only for
          // `liveSegmented`, so there's one fewer conditional camera-arg
          // branch to keep in sync -- this is what `liveSegmented`'s
          // per-segment camera slicing (see `_maybeSealSegment`) actually
          // reads from mid-recording.
          final List<String> cameraArgs = Platform.isMacOS
              ? [
                  '-y',
                  '-stats_period', '0.1',
                  '-f', 'avfoundation',
                  '-i', device,
                  '-c:v', 'libx264',
                  '-preset', 'veryfast',
                  '-pix_fmt', 'yuv420p',
                  '-movflags', 'frag_keyframe+empty_moov+default_base_moof',
                  p.join(sessionDir.path, 'camera.mp4'),
                ]
              : [
                  '-y',
                  '-stats_period', '0.1',
                  '-f', 'dshow',
                  '-i', 'video=$device',
                  '-c:v', 'libx264',
                  '-preset', 'veryfast',
                  '-pix_fmt', 'yuv420p',
                  '-movflags', 'frag_keyframe+empty_moov+default_base_moof',
                  p.join(sessionDir.path, 'camera.mp4'),
                ];
          _cameraProcess = await Process.start(ffmpegPath, cameraArgs);
          // See the "Windows Job Object" section above this class -- ties
          // this process's lifetime to the app's so a hard-kill can't
          // orphan it holding the webcam locked.
          _tieProcessLifetimeToApp(_cameraProcess!.pid);
          _cameraProcess!.stdin.done.catchError((_) {});

          // IMPORTANT: We must consume stdout and stderr, otherwise the OS
          // pipe buffer fills up with ffmpeg's continuous status output and
          // causes ffmpeg to freeze permanently. This same stderr listener
          // doubles as the readiness signal below -- ffmpeg writes a
          // `frame=` progress line to stderr for every frame it actually
          // encodes, so the first one appearing is real confirmation the
          // device is open and producing frames, not a guess.
          final Completer<void> cameraReady = Completer<void>();
          _cameraProcess!.stdout.listen((_) {});
          _cameraProcess!.stderr.listen((List<int> data) {
            if (!cameraReady.isCompleted &&
                utf8.decode(data, allowMalformed: true).contains('frame=')) {
              cameraReady.complete();
            }
          });

          // Bounded wait -- a camera that never opens (driver hang, device
          // held by another app) must never block the recording from
          // starting at all, so this falls back to proceeding anyway after
          // a few seconds, same as every other camera failure path here
          // only ever disabling the camera, never the recording itself.
          try {
            await cameraReady.future.timeout(const Duration(seconds: 5));
          } on TimeoutException {
            onCameraWarning?.call(
              'Camera is taking a while to start -- continuing without waiting further.',
            );
          }

          _cameraEnabled = true;
        }
      } catch (e) {
        await _stopCameraCapture();
        _cameraEnabled = false;
        onCameraWarning?.call('Could not start the camera -- recording without it.');
      }
    } else if (cameraEncodeMode == CameraEncodeMode.externalCompositor) {
      // Runs regardless of `includeCamera` -- this mode's native module
      // handles the ENTIRE video side (window capture, plus an optional
      // camera overlay), not just the camera, so it always starts here.
      // See `CameraEncodeMode.externalCompositor`'s doc comment.
      try {
        final String? device = includeCamera ? await _detectCameraDeviceName() : null;
        if (includeCamera && device == null) {
          onCameraWarning?.call('No camera was found -- recording without one.');
        }
        _externalCompositor = NativeExternalCompositor.start(
          cameraDeviceName: device ?? '',
          outputPath: p.join(sessionDir.path, 'compositor_output.mp4'),
          fps: _encodeFpsFor(frameRateMode),
        );
        _cameraEnabled = device != null;
      } catch (e) {
        _externalCompositor?.dispose();
        _externalCompositor = null;
        _cameraEnabled = false;
        onCameraWarning?.call(
          includeCamera
              ? 'Could not start recording with the camera -- try Standard or Live instead.'
              : 'Could not start the external compositor -- try Standard or Live instead.',
        );
      }
    }

    // The video timeline's zero point -- set only now. For the ffmpeg
    // camera path this is AFTER the camera has either confirmed it's
    // producing real frames or given up waiting, so there's no lag left
    // for it to correct for either (see `_cameraStartOffsetSeconds` just
    // below). Every OTHER capture stream's actual start latency is still
    // measured relative to THIS instant and compensated for at mux time
    // in `encode()` via ffmpeg's `-itsoffset`.
    _startedAt = DateTime.now();
    elapsed = Duration.zero;
    _lastEmittedElapsed = Duration.zero;
    // No lag left to compensate for on the ffmpeg camera path -- see the
    // comment above. Immediately superseded below for the native path,
    // once its real measured timestamp is available.
    _cameraStartOffsetSeconds = 0.0;
    if (_nativeCamera != null) {
      // Doesn't block `start()` -- the native module captures the real
      // first-frame timestamp on its own worker thread regardless of
      // when anyone reads it, so this just polls cheaply for it to show
      // up and folds it into `_cameraStartOffsetSeconds` whenever it
      // does. `stop()`/`encode()` happen long after a recording begins,
      // so there's always plenty of time for this to resolve first.
      unawaited(_resolveNativeCameraOffset(_nativeCamera!, _startedAt!));
    }

    // Audio uses the same native-vs-existing split as the camera -- see
    // `_nativeAudio`'s doc comment for why this applies regardless of
    // `includeCamera`. `audioWavPath` is used by both branches so
    // downstream `encode()` never needs to know which one actually wrote
    // it.
    final String audioWavPath = p.join(sessionDir.path, 'audio.wav');
    final bool useNativeAudio = !Platform.isMacOS && cameraSyncMethod == CameraSyncMethod.nativePrecise;
    _nativeAudio = null;
    // No lag left to compensate for once the native path's real
    // measurement lands -- immediately superseded below once it does,
    // same as `_cameraStartOffsetSeconds`'s reset just above.
    _audioStartOffsetSeconds = 0.0;
    if (useNativeAudio) {
      try {
        _nativeAudio = NativeAudioCapture.start(
          audioWavPath,
          useRawCapture: micEnhancementMode == MicEnhancementMode.disabled,
        );
      } catch (e) {
        await _stopCameraCapture();
        _stopNativeCameraCapture();
        try {
          if (await sessionDir.exists()) {
            await sessionDir.delete(recursive: true);
          }
        } catch (_) {}
        throw MathPadRecordingException('Could not start audio recording: $e');
      }
      // Doesn't block `start()`, same reasoning as
      // `_resolveNativeCameraOffset`'s own doc comment.
      unawaited(_resolveNativeAudioOffset(_nativeAudio!, _startedAt!));
    } else {
      try {
        final bool allowMicEnhancement = micEnhancementMode == MicEnhancementMode.enabled;
        await _audioRecorder.start(
          RecordConfig(
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
            // Tutor-selectable via `micEnhancementMode` (see its doc
            // comment) -- when disabled (the default), these stay off: on
            // Windows they activate the OS APO (Audio Processing Objects)
            // pipeline, which can distort clean narration when there's
            // nothing real to cancel, and can mistake a sustained,
            // unvarying sound for background noise and gate it out
            // partway through. Volume normalisation is handled separately
            // at encode time via dynaudnorm (see below) either way.
            // echoCancel stays off regardless of this setting -- it
            // exists for two-way call scenarios with live speaker
            // feedback, not a solo narration recording.
            autoGain: allowMicEnhancement,
            noiseSuppress: allowMicEnhancement,
          ),
          path: audioWavPath,
        );
      } catch (e) {
        await _stopCameraCapture();
        _stopNativeCameraCapture();
        try {
          if (await sessionDir.exists()) {
            await sessionDir.delete(recursive: true);
          }
        } catch (_) {}
        throw MathPadRecordingException('Could not start audio recording: $e');
      }
      // `_audioRecorder.start()` resolving is the earliest confirmation
      // the mic is actually capturing -- the true start happened
      // SOMEWHERE in the interval between `_startedAt` and now, but
      // "now" is the soonest-available, safe upper-bound estimate
      // (assuming it started any later would risk clipping real
      // narration off the front of the muxed track). Zero, not negative,
      // since a `-itsoffset` compensating for audio starting AFTER the
      // video's t=0 needs the audio pushed later in the output timeline
      // -- see its use in `encode()`.
      _audioStartOffsetSeconds = max(
        0.0,
        DateTime.now().difference(_startedAt!).inMicroseconds / 1e6,
      );
    }

    // Snapshotted once here from `frameRateMode` -- see
    // `RecordingFrameRateMode`'s doc comment. Fixed for this recording's
    // whole duration even if the tutor changes the setting afterward
    // (the settings UI disables the picker while a recording is active).
    _activeCaptureFps = _captureFpsFor(frameRateMode);
    _activeEncodeFps = _encodeFpsFor(frameRateMode);

    // Same snapshotting reasoning as the fps fields just above.
    _activeCameraEncodeMode = cameraEncodeMode;
    _activeIncludeCamera = includeCamera;
    // `continuousStream` can't merge in a SEPARATELY-captured camera
    // stream (no assembly pass left to do that merging in) -- silently
    // falls back to `snapshotBased` for this recording rather than
    // failing outright or (worse) silently dropping the camera. Doesn't
    // apply to `onCanvas` (already baked into what gets captured) or no
    // camera at all. See `RecordingPipelineMode.continuousStream`'s doc
    // comment.
    final bool pipelineCameraConflict =
        includeCamera &&
        cameraEncodeMode != CameraEncodeMode.onCanvas &&
        recordingPipelineMode == RecordingPipelineMode.continuousStream;
    _activeRecordingPipelineMode =
        pipelineCameraConflict ? RecordingPipelineMode.snapshotBased : recordingPipelineMode;
    _continuousStreamProcess = null;
    _continuousStreamProcessExited = false;
    _continuousStreamWidth = 0;
    _continuousStreamHeight = 0;
    _continuousStreamOutputPath = null;
    _lastContinuousStreamFrameBytes = null;
    _continuousStreamFrameCount = 0;

    _sessionDir = sessionDir;
    _canvasKey = canvasKey;
    _frameCount = 0;
    _lastFrameBytes = null;
    _writtenFrameIndex = 0;
    _concatEntries.clear();
    _sealedSegmentPaths.clear();
    _sealedConcatEntryCount = 0;
    _sealedTimelineSeconds = 0.0;
    encodingProgress = 0.0;

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
      Duration(milliseconds: 1000 ~/ _activeCaptureFps),
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
    return (DateTime.now().difference(_startedAt!).inMilliseconds *
                _activeCaptureFps /
                1000)
        .floor();
  }

  Future<void> _captureFrame() async {
    if (_sessionDir == null || _startedAt == null) return;

    // Always keep elapsed time updated
    elapsed = DateTime.now().difference(_startedAt!);

    // Entirely separate capture path -- see `_captureFrameContinuousStream`'s
    // doc comment for why this branches out this early rather than
    // sharing any of the snapshot-based logic/state below.
    if (_activeRecordingPipelineMode == RecordingPipelineMode.continuousStream) {
      await _captureFrameContinuousStream();
      _emitElapsedTick();
      return;
    }

    // `CameraEncodeMode.externalCompositor` doesn't use Flutter's own
    // frame capture AT ALL -- the native module handles the entire video
    // side itself (see that enum value's doc comment). This just keeps
    // `elapsed`/the recording-badge timer ticking; nothing else in this
    // function has any work to do for this mode.
    if (_activeCameraEncodeMode == CameraEncodeMode.externalCompositor) {
      _emitElapsedTick();
      return;
    }

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
      // NOTE: deliberately NOT also checking `renderObject.debugNeedsPaint`
      // here (a prior version of this condition did) -- per its own doc
      // comment in the Flutter framework source, that getter "is only set
      // in debug mode... In release builds, this throws." It's implemented
      // as a `late` variable only ever assigned inside an `assert(...)`,
      // which release builds strip entirely -- so reading it in release
      // unconditionally throws `LateInitializationError`, every single
      // capture attempt, silently swallowed by the `catch` below. That
      // meant recording was completely broken in release builds (nothing
      // ever got past this `if`, so `_concatEntries` stayed empty for the
      // whole recording and `encode()` always failed with "Nothing was
      // captured") while looking totally fine in a debug run, where
      // asserts DO execute.
      if (renderObject is RenderRepaintBoundary && renderObject.attached) {
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
          final double durationSeconds = slotsElapsed / _activeCaptureFps;

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
          final double durationSeconds = slotsElapsed / _activeCaptureFps;
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

  /// The `continuousStream` counterpart to the snapshot-based capture
  /// logic just above -- see `RecordingPipelineMode.continuousStream`'s
  /// doc comment. Extracts raw RGBA pixels (skipping PNG-encoding
  /// entirely -- cheaper per frame than the snapshot path, not just
  /// different) and writes them straight into a continuously-running
  /// ffmpeg process's stdin, lazily spawning that process on the very
  /// first frame so its fixed pipe dimensions match whatever this
  /// recording's capture area actually renders at, rather than a guess
  /// made before any frame existed.
  ///
  /// Entirely self-contained -- its own in-flight guard, its own frame
  /// counter (`_continuousStreamFrameCount`, ticked against
  /// `_activeEncodeFps` directly, not `_activeCaptureFps`, since there's
  /// no separate capture-then-resample step here the way the snapshot
  /// path has via `-r $encodeFps` at encode time -- whatever rate frames
  /// get fed at IS the output rate). Never touches `_frameCount`,
  /// `_concatEntries`, `_lastFrameBytes`, or any segment-sealing state --
  /// those stay exclusively the snapshot path's, so the two pipelines
  /// can never cross-contaminate each other's state.
  Future<void> _captureFrameContinuousStream() async {
    if (_continuousStreamCaptureInFlight || _startedAt == null) return;
    final int fillTo =
        (DateTime.now().difference(_startedAt!).inMilliseconds *
                    _activeEncodeFps /
                    1000)
                .floor();
    if (fillTo <= _continuousStreamFrameCount) return;

    _continuousStreamCaptureInFlight = true;
    try {
      final RenderObject? renderObject = _canvasKey?.currentContext?.findRenderObject();
      if (renderObject is RenderRepaintBoundary && renderObject.attached) {
        final double pixelRatio = min(
          ui.PlatformDispatcher.instance.views.first.devicePixelRatio,
          _maxCapturePixelRatio,
        );
        final ui.Image image = await renderObject.toImage(pixelRatio: pixelRatio);
        final ByteData? bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final int capturedWidth = image.width;
        final int capturedHeight = image.height;
        image.dispose();
        if (bytes != null) {
          if (_continuousStreamProcess == null && !_continuousStreamProcessExited) {
            // First frame -- fixes the pipe's dimensions for the whole
            // recording (a raw-video pipe can't change size mid-stream).
            try {
              await _startContinuousStreamEncoder(capturedWidth, capturedHeight);
            } catch (_) {
              // A genuine spawn failure (e.g. ffmpeg missing/unreadable) --
              // give up on this recording's encoder for good rather than
              // retrying every single tick for the rest of the recording.
              // Without this, the outer catch below swallows the
              // exception without setting the flag, and the check above
              // stays true forever.
              _continuousStreamProcessExited = true;
            }
          }
          if (capturedWidth == _continuousStreamWidth &&
              capturedHeight == _continuousStreamHeight) {
            _lastContinuousStreamFrameBytes = bytes.buffer.asUint8List();
          }
          // else: the capture area's pixel size changed mid-recording
          // (e.g. the window was resized) -- this pipeline can't adapt
          // mid-stream (see the mode's doc comment), so this one frame
          // is dropped; whatever was previously cached gets re-written
          // below instead, same as any other due tick with nothing new.
        }
      }

      final Uint8List? rawBytes = _lastContinuousStreamFrameBytes;
      final Process? process = _continuousStreamProcess;
      if (rawBytes != null && process != null && !_continuousStreamProcessExited) {
        // Every due tick needs a frame WRITTEN, unlike the snapshot
        // path's duration-extension trick -- a raw stream has no
        // metadata channel to say "hold this frame N ticks longer", so
        // an unchanged board still costs one cheap pipe write per tick
        // (re-sending the same cached bytes), just never the expensive
        // toImage()/rasterize call that produced them.
        final int slotsElapsed = fillTo - _continuousStreamFrameCount;
        for (int i = 0; i < slotsElapsed; i++) {
          try {
            process.stdin.add(rawBytes);
          } catch (_) {
            _continuousStreamProcessExited = true;
            break;
          }
        }
        _continuousStreamFrameCount = fillTo;
      }
    } catch (_) {
      // One missed frame isn't worth aborting the whole recording over --
      // same philosophy as the snapshot path.
    } finally {
      _continuousStreamCaptureInFlight = false;
    }
  }

  /// Spawns the long-running ffmpeg process `_captureFrameContinuousStream`
  /// feeds raw frames into, fixed at [width]x[height] for the rest of
  /// this recording. `-bf 0` for the same reason `_encodeSegment` uses it
  /// -- moot for THIS process alone (nothing gets stream-copy-concatenated
  /// with it), kept for consistency with the other two encode paths in
  /// this file and in case a future feature ever needs to splice a
  /// continuous-stream recording with something else.
  Future<void> _startContinuousStreamEncoder(int width, int height) async {
    final String ffmpegPath = _resolveFfmpegPath();
    final String outPath = p.join(_sessionDir!.path, 'canvas_stream.mp4');
    final Process process = await Process.start(ffmpegPath, [
      '-y',
      '-f', 'rawvideo',
      '-pixel_format', 'rgba',
      '-video_size', '${width}x$height',
      '-framerate', '$_activeEncodeFps',
      '-i', 'pipe:0',
      '-vf', 'scale=trunc(iw/2)*2:trunc(ih/2)*2',
      '-c:v', 'libx264',
      '-pix_fmt', 'yuv420p',
      '-preset', 'veryfast',
      '-crf', '20',
      '-bf', '0',
      outPath,
    ]);
    // See the "Windows Job Object" section above this class -- ties this
    // process's lifetime to the app's, same as every other ffmpeg
    // process this file spawns.
    _tieProcessLifetimeToApp(process.pid);
    process.stdin.done.catchError((_) {});
    // Must be consumed or the OS pipe buffer fills and ffmpeg freezes --
    // same reasoning as every other spawned ffmpeg process in this file.
    process.stdout.listen((_) {});
    process.stderr.listen((_) {});
    process.exitCode.then((_) {
      _continuousStreamProcessExited = true;
    }).catchError((_) {});
    _continuousStreamProcess = process;
    _continuousStreamProcessExited = false;
    _continuousStreamWidth = width;
    _continuousStreamHeight = height;
    _continuousStreamOutputPath = outPath;
  }

  /// Closes the continuous-stream encoder's stdin (if one was started)
  /// and waits for ffmpeg to finalize the file -- the `continuousStream`
  /// counterpart to `_stopCameraCapture()`. Returns the finished video's
  /// path (already fully encoded -- canvas, and camera too if
  /// `CameraEncodeMode.onCanvas` composited it in live -- by the time
  /// this returns) or null if this recording never actually started one
  /// (wrong pipeline mode, or no frame was ever captured to trigger the
  /// lazy spawn).
  Future<String?> _stopContinuousStreamEncoder() async {
    final Process? process = _continuousStreamProcess;
    final String? outPath = _continuousStreamOutputPath;
    _continuousStreamProcess = null;
    _continuousStreamProcessExited = true;
    if (process == null) return null;
    try {
      await process.stdin.flush();
    } catch (_) {}
    try {
      await process.stdin.close();
    } catch (_) {}
    try {
      final int exitCode = await process.exitCode.timeout(const Duration(seconds: 10));
      if (exitCode != 0) {
        return null;
      }
    } catch (_) {
      process.kill(ProcessSignal.sigkill);
      return null;
    }
    if (outPath != null && await File(outPath).exists() && (await File(outPath).length()) > 0) {
      return outPath;
    }
    return null;
  }

  /// Builds a concat-demuxer manifest for exactly [entries] and encodes it
  /// with the bundled ffmpeg into one MPEG-TS segment at [outPath] --
  /// shared by the periodic background seal below and by `encode()`'s
  /// final leftover-tail segment, so both produce segments in exactly the
  /// same format (required for the fast `-c copy` concat that joins them
  /// all together afterward). Returns false (never throws) on any
  /// failure, so a failed segment just means more work happens at the
  /// final encode instead -- never worth losing the recording over.
  ///
  /// [cameraFilePath]/[cameraStartOffsetSeconds]/[segmentStartSeconds]
  /// are all-or-nothing together -- when given, this segment gets the
  /// picture-in-picture camera overlay baked in directly (see
  /// `CameraEncodeMode.liveSegmented`'s doc comment), using the SAME
  /// fixed, non-drifting offset for every segment (never re-estimated
  /// per call) to locate exactly which slice of the (fragmented, so
  /// readable mid-recording) camera file corresponds to
  /// [segmentStartSeconds] on the shared canvas timeline. Called both
  /// live (`_maybeSealSegment`, while recording continues) and for the
  /// leftover tail (`encode()`, once stopped) -- identical either way,
  /// so a segment sealed live and one encoded at the very end are
  /// byte-for-byte produced by the same logic.
  Future<bool> _encodeSegment({
    required Directory sessionDir,
    required List<_ConcatEntry> entries,
    required String outPath,
    required String preset,
    required String crf,
    required int encodeFps,
    String? cameraFilePath,
    double? cameraStartOffsetSeconds,
    double segmentStartSeconds = 0.0,
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

      final double segmentDurationSeconds = entries.fold(
        0.0,
        (sum, e) => sum + e.durationSeconds,
      );
      // No camera footage exists yet for a segment that falls entirely
      // before the camera's own measured start -- happens at most once,
      // for whichever segment straddles or precedes that instant (in
      // practice only ever the very first one). Falls back to a plain
      // canvas-only encode for just that segment, matching exactly what
      // the finalPass path's overlay filter would show (nothing) for
      // that same stretch anyway.
      final bool includeCameraOverlay =
          cameraFilePath != null &&
          cameraStartOffsetSeconds != null &&
          (segmentStartSeconds + segmentDurationSeconds) >
              cameraStartOffsetSeconds + 0.0005;

      final List<String> args;
      if (includeCameraOverlay) {
        // How much of THIS segment's own start still falls before the
        // camera actually began -- nonzero only for the one segment
        // straddling that instant, pushing the camera's appearance in
        // THIS segment's output later by exactly that much, same
        // `-itsoffset` idea `encodeCanvasWithCamera()` applies once for
        // the whole recording, just scoped to one segment here. Every
        // later segment has already passed that instant, so this is 0.
        final double residualItsOffset = (cameraStartOffsetSeconds - segmentStartSeconds)
            .clamp(0.0, double.infinity);
        // Where in the camera's OWN file this segment's footage actually
        // lives -- simple subtraction against the one fixed offset, not
        // a re-estimate, so this never drifts across segments the way
        // the earlier, reverted attempt at this did.
        final double cameraSliceStart = (segmentStartSeconds - cameraStartOffsetSeconds)
            .clamp(0.0, double.infinity);
        final double cameraSliceDuration = segmentDurationSeconds - residualItsOffset;

        args = [
          '-y',
          '-f', 'concat',
          '-safe', '0',
          '-i', manifestFile.path,
          if (residualItsOffset > 0.0005)
            ...['-itsoffset', residualItsOffset.toStringAsFixed(6)],
          '-ss', cameraSliceStart.toStringAsFixed(6),
          '-t', cameraSliceDuration.toStringAsFixed(6),
          '-i', cameraFilePath,
          // Identical filter graph to `encodeCanvasWithCamera()`'s (same
          // box size/position/border) -- see that function's comment for
          // what each piece does. Kept in sync manually since ffmpeg has
          // no way to share a filter-graph fragment across separate
          // invocations.
          '-filter_complex',
          // `fps=$encodeFps` on BOTH [0:v] and [1:v] (not just the base)
          // -- the camera's own native capture rate is essentially never
          // an exact match for `encodeFps` (a real webcam commonly runs
          // something like 29.35fps against a 30fps target), so without
          // explicitly conforming it too, `overlay` has to pick which of
          // its irregularly-timed input frames lines up with each base
          // frame using its own internal PTS-nearest-match logic. In one
          // continuous whole-recording pass that rounding is smoothed
          // out invisibly across the whole video -- but each segment
          // here is an independently restarted overlay computation, so
          // that same rounding shows up as a small, localized frame
          // skip/repeat right at the start of every segment instead.
          // Conforming both sides to the identical explicit rate before
          // they ever reach `overlay` removes the ambiguity it would
          // otherwise have to round away.
          '[0:v]fps=$encodeFps,scale=trunc(iw/2)*2:trunc(ih/2)*2[base];'
              '[1:v]fps=$encodeFps,crop=ih:ih,scale=w=240:h=240,'
              'drawbox=x=0:y=0:w=iw:h=ih:color=white@0.9:t=4[cam];'
              '[base][cam]overlay=x=main_w-overlay_w-24:y=24[outv]',
          '-map', '[outv]',
          // REQUIRED -- confirmed by direct testing, not an assumption:
          // without an explicit output duration bound, this filter_complex
          // (unlike the plain `-vf` path just below) doesn't reliably stop
          // at the canvas segment's own intended length. It ran to the
          // CAMERA input's full sliced-plus-whatever duration instead
          // (10s canvas content produced a 10s output when the camera clip
          // was also ~10s, rather than the canvas's actual 5s) -- overlay's
          // `eof_action=repeat` default handles a camera shorter than the
          // segment (freezes on its last frame, doesn't end early); this
          // handles the segment needing to end exactly on time regardless.
          '-t', segmentDurationSeconds.toStringAsFixed(6),
          '-c:v', 'libx264',
          '-pix_fmt', 'yuv420p',
          '-preset', preset,
          '-crf', crf,
          // See the `-bf 0` comment on the plain-canvas branch just
          // below -- applies equally here.
          '-bf', '0',
          '-f', 'mpegts',
          outPath,
        ];
      } else {
        args = [
          '-y',
          '-f', 'concat',
          '-safe', '0',
          '-i', manifestFile.path,
          '-r', '$encodeFps',
          '-vf', 'scale=trunc(iw/2)*2:trunc(ih/2)*2',
          '-c:v', 'libx264',
          '-pix_fmt', 'yuv420p',
          '-preset', preset,
          '-crf', crf,
          // No B-frames in ANY segment that might get stream-copy-
          // concatenated with another later (every segment this function
          // produces does, live-sealed or the tail -- see `encode()`'s
          // `-c:v copy` fast path). A B-frame references frames on BOTH
          // sides of it, requiring the decoder to reorder frames in its
          // playback buffer -- exactly what gets confused right at a
          // splice between two independently-encoded streams, since the
          // reordering context from one segment's encoder session means
          // nothing to the next one's. A plain, B-frame-free IPPP...
          // stream removes that ambiguity entirely, since there's
          // nothing left to reorder across the join. The standard fix
          // for stutter/hitches at segment splice points in exactly this
          // kind of stream-copy-concatenated recording. Slightly larger
          // files at the same CRF (B-frames are what give H.264 most of
          // its extra compression efficiency) -- a fair trade for a
          // splice-safe recording.
          '-bf', '0',
          '-f', 'mpegts',
          outPath,
        ];
      }

      final ProcessResult result = await Process.run(ffmpegPath, args);
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
      final double segmentStartSeconds = _sealedTimelineSeconds;
      // Bakes the camera overlay into this segment right now, live,
      // instead of leaving it for one whole-recording pass at the end --
      // see `CameraEncodeMode.liveSegmented`'s doc comment. Gated on
      // `_cameraEnabled` (not just the mode) so a recording where the
      // camera failed to start at all just seals plain canvas segments,
      // same as always. NOTE: for `CameraSyncMethod.nativePrecise`,
      // `_cameraStartOffsetSeconds` resolves asynchronously in the
      // background (see `_resolveNativeCameraOffset`) -- if the very
      // FIRST seal happens unusually fast (an idle-triggered seal within
      // the first second or so), it could in principle still be at its
      // 0.0 default here, producing a slightly-off camera slice for just
      // that one segment. Same "best-effort, never fatal" tradeoff as
      // everywhere else camera timing is handled in this file.
      final bool bakeCameraIn =
          _activeCameraEncodeMode == CameraEncodeMode.liveSegmented && _cameraEnabled;
      // Same fixed "normal quality" preset the tail segment and the
      // single-pass path both use -- every segment in a recording (sealed
      // in the background or the leftover tail encoded once stopped) is
      // encoded identically, so there's nothing to reconcile at `encode()`
      // time. `_activeEncodeFps` -- this runs live, mid-recording.
      final bool ok = await _encodeSegment(
        sessionDir: dir,
        entries: toSeal,
        outPath: segmentPath,
        preset: 'veryfast',
        crf: '20',
        encodeFps: _activeEncodeFps,
        cameraFilePath: bakeCameraIn ? p.join(dir.path, 'camera.mp4') : null,
        cameraStartOffsetSeconds: bakeCameraIn ? _cameraStartOffsetSeconds : null,
        segmentStartSeconds: segmentStartSeconds,
      );
      if (ok) {
        _sealedSegmentPaths.add(segmentPath);
        _sealedConcatEntryCount += toSeal.length;
        _sealedTimelineSeconds =
            segmentStartSeconds + toSeal.fold(0.0, (sum, e) => sum + e.durationSeconds);
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
    if (_nativeAudio != null) {
      final NativeAudioCapture audio = _nativeAudio!;
      _nativeAudio = null;
      final bool finalizedOk = audio.stop();
      // Same fixed filename regardless of which capture path wrote it --
      // see `useNativeAudio`'s doc comment in `start()`.
      audioPath = finalizedOk ? p.join(_sessionDir!.path, 'audio.wav') : null;
      audio.dispose();
    } else {
      try {
        audioPath = await _audioRecorder.stop();
      } catch (e) {
        audioPath = null;
      }
    }

    // Let any in-flight frame capture -- and any in-flight background
    // segment seal -- finish before we freeze state, so `encode()` always
    // sees a fully consistent `_sealedSegmentPaths`/`_sealedConcatEntryCount`
    // pair (a seal that's still mid-flight when this runs could otherwise
    // finish afterward and mutate state nobody's looking at anymore).
    while (_captureInFlight || _segmentSealInFlight || _continuousStreamCaptureInFlight) {
      await Future.delayed(const Duration(milliseconds: 20));
    }

    await _stopCameraCapture();
    _stopNativeCameraCapture();
    // No-op (returns null immediately) unless `_activeRecordingPipelineMode`
    // was actually `continuousStream` for this recording -- see
    // `_stopContinuousStreamEncoder`'s doc comment.
    _capturedContinuousStreamOutputPath = await _stopContinuousStreamEncoder();
    _capturedContinuousStreamDurationSeconds =
        _activeEncodeFps > 0 ? _continuousStreamFrameCount / _activeEncodeFps : 0.0;
    // No-op (returns null) unless `_activeCameraEncodeMode` was actually
    // `externalCompositor` for this recording. Blocking, same as the
    // other two native-module stops above -- the underlying FFI call
    // waits for the native worker thread (window capture + optional
    // camera composite + the piped ffmpeg process) to fully finish.
    if (_externalCompositor != null) {
      final NativeExternalCompositor compositor = _externalCompositor!;
      _externalCompositor = null;
      final String outPath = p.join(_sessionDir!.path, 'compositor_output.mp4');
      final bool finalizedOk = compositor.stop();
      final File outFile = File(outPath);
      _capturedExternalCompositorOutputPath =
          (finalizedOk && await outFile.exists() && await outFile.length() > 0) ? outPath : null;
      compositor.dispose();
    } else {
      _capturedExternalCompositorOutputPath = null;
    }
    // The native module doesn't report its own frame count back to
    // Dart -- `elapsed` (kept updated every tick even for this mode,
    // see `_captureFrame`'s early-return branch) is a close enough
    // proxy for the real video duration, only used for the encode
    // progress bar's percentage math, never for correctness.
    _capturedExternalCompositorDurationSeconds = elapsed.inMicroseconds / 1e6;

    _capturedConcatEntries = List.of(_concatEntries);
    _capturedSessionDir = _sessionDir;
    _capturedCameraWasEnabled = _cameraEnabled;
    _capturedAudioPath = audioPath;
    _capturedAudioStartOffsetSeconds = _audioStartOffsetSeconds;
    _capturedCameraStartOffsetSeconds = _cameraStartOffsetSeconds;
    _capturedSealedSegmentPaths = List.of(_sealedSegmentPaths);
    _capturedSealedConcatEntryCount = _sealedConcatEntryCount;
    _capturedSealedTimelineSeconds = _sealedTimelineSeconds;
    _capturedActiveCameraEncodeMode = _activeCameraEncodeMode;
    _capturedActiveRecordingPipelineMode = _activeRecordingPipelineMode;
    _capturedEncodeFps = _activeEncodeFps;
    _capturedAudioBitrateKbps = _audioKbpsFor(audioBitrateMode);

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
    // Frees the cached raw-frame buffer promptly rather than waiting for
    // the next `start()`'s own reset -- see the "continuousStream state"
    // field group's doc comment above.
    _lastContinuousStreamFrameBytes = null;
    _continuousStreamWidth = 0;
    _continuousStreamHeight = 0;
    _continuousStreamOutputPath = null;
    _continuousStreamFrameCount = 0;
    _continuousStreamProcessExited = false;
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
  /// Finalizes a `RecordingPipelineMode.continuousStream` recording --
  /// [rawVideoPath] is already a complete, fully-encoded H.264 video (see
  /// `_startContinuousStreamEncoder`/`_stopContinuousStreamEncoder`) by
  /// the time this runs, so there's no canvas manifest, no segment
  /// concat, no camera overlay pass here at all -- just a quick mux with
  /// the separately-captured audio (`-c:v copy`, no video re-encoding),
  /// or a straight file copy if there's no audio to add. This is the
  /// entire reason this pipeline mode exists: finishes almost instantly
  /// regardless of how long the recording was.
  Future<String> _finalizeContinuousStreamRecording({
    required String rawVideoPath,
    required Directory sessionDir,
    required String? audioPath,
    required double audioStartOffsetSeconds,
    required int audioKbps,
    required double totalDurationSeconds,
  }) async {
    Future<void> cleanup() async {
      if (await sessionDir.exists()) {
        await sessionDir.delete(recursive: true);
      }
    }
    try {
      final Directory outDir = await getRecordingsDir();
      final String outPath =
          p.join(outDir.path, 'MathPad_${DateTime.now().millisecondsSinceEpoch}.mp4');

      if (audioPath != null) {
        final String ffmpegPath = _resolveFfmpegPath();
        await _runFfmpegWithProgress(ffmpegPath, [
          '-y',
          '-progress', 'pipe:1',
          '-nostats',
          '-i', rawVideoPath,
          // Same reasoning as every other audio mux in this file -- see
          // `_audioStartOffsetSeconds`'s doc comment.
          if (audioStartOffsetSeconds > 0.0005)
            ...['-itsoffset', audioStartOffsetSeconds.toStringAsFixed(6)],
          '-i', audioPath,
          '-map', '0:v',
          '-map', '1:a',
          // The video is already fully encoded -- copy, don't re-encode.
          '-c:v', 'copy',
          '-af', 'dynaudnorm=framelen=500:gausssize=31:peak=0.95',
          // See the other encode paths' identical comment on why this is
          // explicit rather than trusting the source WAV's own format.
          '-ar', '48000',
          '-ac', '1',
          '-c:a', 'aac',
          '-b:a', '${audioKbps}k',
          '-shortest',
          outPath,
        ], totalDurationSeconds);
      } else {
        // No audio at all (a mic failure) -- the video is already the
        // final file, just needs to live in the recordings folder.
        await File(rawVideoPath).copy(outPath);
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

  Future<String> encode() async {
    if (_state != MathPadRecordingState.waitingForEncodeChoice) {
      throw MathPadRecordingException('Not waiting for encode.');
    }

    final Directory? sessionDir = _capturedSessionDir;
    if (sessionDir == null) {
      _state = MathPadRecordingState.idle;
      _emit();
      throw MathPadRecordingException('No active recording session found.');
    }

    final List<_ConcatEntry> concatEntries = _capturedConcatEntries ?? [];
    final bool cameraWasEnabled = _capturedCameraWasEnabled;
    final String? audioPath = _capturedAudioPath;
    final double audioStartOffsetSeconds = _capturedAudioStartOffsetSeconds;
    final double cameraStartOffsetSeconds = _capturedCameraStartOffsetSeconds;
    final int encodeFps = _capturedEncodeFps;
    final int audioKbps = _capturedAudioBitrateKbps;

    _state = MathPadRecordingState.encoding;
    _emit();

    Future<void> cleanup() async {
      try {
        if (await sessionDir.exists()) {
          await sessionDir.delete(recursive: true);
        }
      } catch (_) {}
    }

    // `RecordingPipelineMode.continuousStream` recordings never populate
    // `concatEntries` at all (see that mode's doc comment) -- checked
    // and handled FIRST, before the "nothing was captured" guard below
    // (which would otherwise misfire for every continuous-stream
    // recording) and before any of the canvas-manifest/segment/camera-
    // merge machinery further down, none of which this mode uses.
    if (_capturedActiveRecordingPipelineMode == RecordingPipelineMode.continuousStream) {
      final String? continuousStreamOutputPath = _capturedContinuousStreamOutputPath;
      if (continuousStreamOutputPath != null &&
          await File(continuousStreamOutputPath).exists() &&
          (await File(continuousStreamOutputPath).length()) > 0) {
        return _finalizeContinuousStreamRecording(
          rawVideoPath: continuousStreamOutputPath,
          sessionDir: sessionDir,
          audioPath: _capturedAudioPath,
          audioStartOffsetSeconds: _capturedAudioStartOffsetSeconds,
          audioKbps: _capturedAudioBitrateKbps,
          totalDurationSeconds: _capturedContinuousStreamDurationSeconds,
        );
      } else {
        await cleanup();
        _state = MathPadRecordingState.idle;
        _emit();
        throw MathPadRecordingException(
          'Continuous stream recording failed -- no video frames were captured.',
        );
      }
    }

    // `CameraEncodeMode.externalCompositor` -- same "check first, before
    // the concatEntries guard below (which would otherwise misfire,
    // since this mode never populates it either)" reasoning as the
    // continuousStream branch just above. Reuses the exact same
    // finalize-mux helper -- both modes hand `encode()` an
    // already-fully-encoded video with nothing left to do but add audio.
    if (_capturedActiveCameraEncodeMode == CameraEncodeMode.externalCompositor) {
      final String? compositorOutputPath = _capturedExternalCompositorOutputPath;
      if (compositorOutputPath != null) {
        return _finalizeContinuousStreamRecording(
          rawVideoPath: compositorOutputPath,
          sessionDir: sessionDir,
          audioPath: _capturedAudioPath,
          audioStartOffsetSeconds: _capturedAudioStartOffsetSeconds,
          audioKbps: _capturedAudioBitrateKbps,
          totalDurationSeconds: _capturedExternalCompositorDurationSeconds,
        );
      } else {
        await cleanup();
        _state = MathPadRecordingState.idle;
        _emit();
        throw MathPadRecordingException(
          'Recording failed -- the external compositor stopped working. '
          'Try the Standard or Live camera encoding option instead.',
        );
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
      // interval), this is simply every captured entry.
      final List<_ConcatEntry> tailEntries =
          concatEntries.length > _capturedSealedConcatEntryCount
          ? concatEntries.sublist(_capturedSealedConcatEntryCount)
          : const [];

      // Whether the camera overlay gets baked directly into each segment
      // (sealed live, plus the tail below) instead of one separate
      // whole-recording pass later -- see `CameraEncodeMode.liveSegmented`'s
      // doc comment. When true, this ALSO forces the segment pipeline
      // below even for a short recording that never sealed anything live
      // (`sealedSegments.isEmpty`) -- the tail then simply covers the
      // entire recording, still baked in exactly the same way, just all
      // at once here instead of spread out live. That's what lets the
      // final step, further down, skip `encodeCanvasWithCamera()`'s
      // separate filter_complex pass entirely: every segment (sealed live
      // or not) already has the camera composited in by the time it's
      // built.
      final bool bakeCameraIntoSegments =
          _capturedActiveCameraEncodeMode == CameraEncodeMode.liveSegmented && hasCamera;

      // The canvas source, as an ffmpeg concat-demuxer manifest -- either
      // the already-encoded background-sealed segments (+ a freshly
      // encoded tail), or the raw captured stills. `canvasPreEncoded`
      // tracks which, since only the sealed-segments case is eligible for
      // a cheap `-c:v copy` when there's no camera to overlay.
      final String canvasManifestPath;
      final bool canvasPreEncoded;
      if (sealedSegments.isNotEmpty || bakeCameraIntoSegments) {
        // ─── Sealed segments + tail ────────────────────────────────────
        // Most of the video is already encoded (sealed periodically in
        // the background throughout the recording -- see
        // `_maybeSealSegment`). Only the small leftover tail needs a real
        // encode here (which, if nothing was ever sealed live, is simply
        // the entire recording -- see `bakeCameraIntoSegments`'s comment).
        final List<String> allSegments = List.of(sealedSegments);
        if (tailEntries.isNotEmpty) {
          final String tailPath = p.join(sessionDir.path, 'segment_tail.ts');
          bool tailOk = await _encodeSegment(
            sessionDir: sessionDir,
            entries: tailEntries,
            outPath: tailPath,
            preset: 'veryfast',
            crf: '20',
            encodeFps: encodeFps,
            cameraFilePath: bakeCameraIntoSegments ? cameraFile.path : null,
            cameraStartOffsetSeconds:
                bakeCameraIntoSegments ? cameraStartOffsetSeconds : null,
            segmentStartSeconds: _capturedSealedTimelineSeconds,
          );
          if (!tailOk && bakeCameraIntoSegments) {
            // The tail is the last-resort step -- unlike a failed LIVE
            // seal (which just falls through to become part of the
            // tail), there's nowhere further for this to fall through
            // to. Retry once without the camera overlay rather than
            // silently losing this stretch of the recording entirely --
            // same "camera trouble costs the camera, never the
            // recording" philosophy as everywhere else camera work is
            // done in this file.
            tailOk = await _encodeSegment(
              sessionDir: sessionDir,
              entries: tailEntries,
              outPath: tailPath,
              preset: 'veryfast',
              crf: '20',
              encodeFps: encodeFps,
            );
            if (tailOk) {
              onCameraWarning?.call(
                'Camera couldn\'t be added to the last part of the video -- that part was saved without it.',
              );
            }
          }
          if (tailOk) allSegments.add(tailPath);
        }

        final StringBuffer segManifest = StringBuffer('ffconcat version 1.0\n');
        for (final seg in allSegments) {
          // Inside an ffconcat `'...'`-quoted token, ffmpeg's own quoting
          // rules ("ffmpeg-utils" -> Quoting and escaping) take everything
          // between the quotes completely literally -- backslash is NOT an
          // escape character there, so a Windows path's backslashes need
          // no handling at all (converting them to `/` first is harmless
          // but not required). The ONE character that can't appear inside
          // `'...'` is `'` itself -- `\'` does NOT escape it (backslash
          // means nothing in quoted mode), it just ends the quoted token
          // early and corrupts the rest of the manifest line. The correct
          // escape is the POSIX-shell-style close/escape/reopen trick:
          // `'\''`.
          final String safeSeg = seg
              .replaceAll(r'\', '/')
              .replaceAll("'", "'\\''");
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
            '-r', '$encodeFps',
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
            // Explicit target format rather than trusting whatever the
            // source WAV happens to be -- the native/precise audio
            // capture path writes the audio engine's own native format
            // (commonly float32 stereo), not the mono 16-bit the
            // `record`-package path always produced, so this is what
            // keeps every recording's narration track mono/48kHz
            // regardless of which one wrote it (see the class doc
            // comment on why mono is enough for a single narrator).
            '-ar', '48000',
            '-ac', '1',
            '-c:a', 'aac',
            '-b:a', '${audioKbps}k',
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
        // In practice this is always 0 now -- `start()` waits for the
        // camera to confirm it's producing real frames before the canvas
        // timeline's t=0 is even set (see `_cameraStartOffsetSeconds`'s
        // doc comment), so there's no lead/lag left to shift out here.
        // The conditional stays as a defensive no-op for the rare case the
        // wait timed out and the field wasn't reset to exactly 0.0.
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
        // `fps=$encodeFps` on the camera input too, not just the base --
        // see the identical fix's comment in `_encodeSegment` for why
        // (a real webcam's native rate essentially never exactly matches
        // `encodeFps`, so this removes the rate-mismatch `overlay` would
        // otherwise have to round away on its own). Barely perceptible
        // in this one-continuous-pass path (the rounding smooths out
        // invisibly across the whole video here), but applied for the
        // same underlying correctness and to keep both camera-overlay
        // filter graphs in this file consistent with each other.
        final String filterComplex =
            '[0:v]fps=$encodeFps,scale=trunc(iw/2)*2:trunc(ih/2)*2[base];'
            '[$cameraInputIndex:v]fps=$encodeFps,crop=ih:ih,scale=w=240:h=240,'
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
          // Defensive bound, confirmed necessary by direct testing on the
          // per-segment version of this same filter graph (see
          // `_encodeSegment`): a filter_complex+overlay pass doesn't
          // reliably self-terminate at the canvas's own length without
          // one. `-shortest` below (when there's audio) already caps this
          // correctly via the real, accurate audio duration -- this is
          // what still catches the rare audio-less camera recording,
          // where `-shortest` never gets added at all.
          '-t', totalDurationSeconds.toStringAsFixed(6),
          '-c:v', 'libx264',
          '-pix_fmt', 'yuv420p',
          '-preset', 'veryfast',
          '-crf', '20',
          if (audioInputIndex != null) ...[
            '-af', 'dynaudnorm=framelen=500:gausssize=31:peak=0.95',
            // See the camera-less encode path above for why this is
            // explicit rather than trusting the source WAV's own format.
            '-ar', '48000',
            '-ac', '1',
            '-c:a', 'aac',
            '-b:a', '${audioKbps}k',
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

      if (hasCamera && !bakeCameraIntoSegments) {
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
        // Either there's no camera to add at all, or (`bakeCameraIntoSegments`)
        // every segment above already has it baked in -- either way, the
        // canvas manifest built above IS the final video already; no
        // separate overlay pass needed. `encodeCanvasOnly()` also handles
        // the `canvasPreEncoded` fast `-c:v copy` path transparently, so
        // this is the same speed win a camera-less recording already got.
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
    while (_segmentSealInFlight || _continuousStreamCaptureInFlight) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    // `cancel()` can be reached from `waitingForEncodeChoice` too (after
    // `stopCapture()` already stopped the mic), where the recorder plugin
    // may throw on a redundant `.stop()` call -- caught here, matching
    // `stopCapture()`'s own handling, so that can never leave `_state`
    // stuck instead of settling back to `idle` below.
    try {
      await _audioRecorder.stop();
    } catch (_) {}
    if (_nativeAudio != null) {
      final NativeAudioCapture audio = _nativeAudio!;
      _nativeAudio = null;
      audio.stop();
      audio.dispose();
    }
    await _stopCameraCapture();
    _stopNativeCameraCapture();
    await _stopContinuousStreamEncoder();
    _capturedContinuousStreamOutputPath = null;
    if (_externalCompositor != null) {
      final NativeExternalCompositor compositor = _externalCompositor!;
      _externalCompositor = null;
      compositor.stop();
      compositor.dispose();
    }
    _capturedExternalCompositorOutputPath = null;
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

  /// `_captureFrame` calls this (not `_emit`) on every tick -- up to
  /// `_activeCaptureFps` times/sec, from both the persistent-frame-callback and the
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
    _continuousStreamProcess?.kill(ProcessSignal.sigkill);
    // No hard-kill equivalent needed for any of the three native capture
    // paths here -- all are in-process worker threads, not separate
    // Dart-visible processes, so none can be orphaned the way
    // `_cameraProcess` can (see `_stopNativeCameraCapture`'s doc
    // comment). The external compositor's OWN internal ffmpeg process
    // has its own independent Job Object protection, set up natively in
    // external_compositor.cpp, for exactly this scenario. Still worth
    // releasing all three native handles here if somehow still around.
    _nativeCamera?.dispose();
    _nativeAudio?.dispose();
    _externalCompositor?.dispose();
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
