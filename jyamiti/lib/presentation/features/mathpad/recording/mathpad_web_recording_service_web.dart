// ============================================================================
// Renamed from mathpad_web_recording_service.dart -- imported conditionally
// now (see mathpad_web_recording_service.dart, the new barrel file) rather
// than directly, since package:web/dart:js_interop are web-specific;
// mathpad_web_recording_service_stub.dart is what every other platform gets
// instead, with the exact same public API. Wired into mathpad.dart's
// toolbar as its own, web-only recording button (kIsWeb-gated) -- a wholly
// SEPARATE implementation from MathPadRecordingService, not a platform
// branch inside it. That file imports dart:io/dart:ffi throughout (real
// files, spawned ffmpeg processes, native FFI) -- none of which exist on
// web, so this couldn't be added there even as a branch. See the design
// discussion that led here for the full reasoning.
//
// Now has camera overlay + best-effort crop-to-canvas, added after the
// first slice (screen-only, no crop) was confirmed actually recording.
//
// UNAVOIDABLE, BY BROWSER DESIGN -- not a bug to fix later:
//   `getDisplayMedia()` always shows the browser's native "choose a
//   window/tab/screen" picker, every time, with no way for any app to
//   skip it. `preferCurrentTab: true` (Chromium) biases the picker's
//   default toward this tab but the user can still pick something else.
//
// CROP-TO-CANVAS -- how it stays honest about the risk flagged in the
// design discussion (there's no way to know for certain the user picked
// "this tab", so cropping blind risks a nonsensical result): after
// getDisplayMedia resolves, the video track's own `getSettings()` is
// inspected for `displaySurface` -- a real (if not universally supported)
// signal for WHAT KIND of source was shared ('browser' | 'window' |
// 'monitor'). The crop rect [mathpad.dart] measured off the canvas
// widget's own RenderBox (same technique the Windows compositor's
// `_measureCanvasCropRect` uses, converted to physical pixels via
// devicePixelRatio) is only ever applied when displaySurface == 'browser'
// -- otherwise this silently falls back to capturing the full shared
// source, same as before crop existed, rather than risk cropping the
// wrong region of a window/monitor capture where the coordinate spaces
// don't correspond. `displaySurface` isn't in package:web's typed
// MediaTrackSettings bindings (a newer/optional spec field) -- read via a
// small custom extension type (_DisplaySurfaceSettings) instead, wrapped
// in a try/catch that treats any failure the same as "don't crop".
//
// CAMERA OVERLAY -- same PIP spec every other camera-overlay path in this
// app uses (crop to square, scale to 240x240, white border, top-right
// 24px inset), drawn via Canvas2D's 9-argument `drawImage` for the
// crop+scale in one call. Best-effort, same "camera trouble costs the
// camera, never the recording" philosophy as every native platform here --
// a getUserMedia failure just means no camera box, not a failed recording.
//
// NOT YET OFF-THREAD -- the real reason the other three platforms'
// compositors are smooth is that capture+composite+encode never touch the
// thread the UI/interaction runs on. The genuine web equivalent (Insertable
// Streams: `MediaStreamTrackProcessor` + `OffscreenCanvas` in a Worker) has
// meaningfully narrower browser support (primarily Chromium) -- shipping
// something that silently doesn't work on a chunk of browsers felt worse
// than being upfront that this still accepts main-thread compositing.
//
// UNVERIFIED IN THE BROWSER, but more verifiable than the native modules:
// `flutter build web` actually compile-checks this file's `package:web`
// API usage -- real compiler errors were found and fixed while writing
// this (both in the original slice and in this camera/crop addition).
// What compiling clean can't confirm: actual runtime behavior (permission
// flow, whether `displaySurface` really reports what's expected, codec
// support, frame timing) -- that needs a real browser, which I don't have.
// ============================================================================

import 'dart:async';
import 'dart:js_interop';
import 'dart:math';

import 'package:web/web.dart' as web;

class MathPadWebRecordingException implements Exception {
  MathPadWebRecordingException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads `MediaTrackSettings.displaySurface` -- not in package:web's typed
/// bindings (a newer/optional part of the Screen Capture spec) -- via a
/// small custom extension type over the same underlying JSObject, rather
/// than needing the older, now-discouraged `dart:js_util`.
extension type _DisplaySurfaceSettings._(JSObject _) implements JSObject {
  external JSString? get displaySurface;
}

class MathPadWebRecordingService {
  web.MediaStream? _screenStream;
  web.MediaStream? _cameraStream;
  web.HTMLVideoElement? _screenVideo;
  web.HTMLVideoElement? _cameraVideo;
  web.HTMLCanvasElement? _canvas;
  web.MediaRecorder? _recorder;
  web.MediaStream? _canvasStream;
  final List<web.Blob> _chunks = [];
  bool _drawLoopActive = false;
  Completer<web.Blob>? _stopCompleter;

  bool get isRecording => _recorder != null;

  /// Shows the browser's screen/tab/window picker (see this file's header
  /// comment -- unavoidable, every time), optionally starts a camera feed
  /// for the PIP overlay, then starts compositing onto an internal canvas
  /// and encoding via `MediaRecorder`. [fps] controls both the draw loop's
  /// target rate and the canvas capture stream's rate.
  ///
  /// [cropRect], if given, is only actually applied when the shared
  /// source's `displaySurface` reports `'browser'` (see this file's header
  /// comment for why) -- otherwise the full shared source is captured,
  /// same as if no crop rect were passed at all.
  ///
  /// Throws [MathPadWebRecordingException] if the user cancels the picker,
  /// the browser doesn't support the required APIs, or no codec
  /// `MediaRecorder` will accept could be found. A camera failure is never
  /// fatal to the recording -- see [_startCamera].
  Future<void> start({
    int fps = 30,
    bool includeCamera = false,
    Rectangle<int>? cropRect,
  }) async {
    if (isRecording) return;

    final web.MediaDevices? mediaDevices = web.window.navigator.mediaDevices;
    if (mediaDevices == null) {
      throw MathPadWebRecordingException(
        'This browser does not support screen recording (no navigator.mediaDevices).',
      );
    }

    late web.MediaStream screenStream;
    try {
      final web.DisplayMediaStreamOptions options = web.DisplayMediaStreamOptions(
        video: true.toJS,
        audio: false.toJS,
      );
      screenStream = await mediaDevices.getDisplayMedia(options).toDart;
    } catch (e) {
      throw MathPadWebRecordingException(
        'Screen sharing was cancelled or denied -- recording needs a '
        'window/tab/screen to be selected.',
      );
    }
    _screenStream = screenStream;

    final web.HTMLVideoElement video = web.HTMLVideoElement()
      ..srcObject = screenStream
      ..muted = true
      ..autoplay = true;
    _screenVideo = video;
    // Wait for the first frame's real dimensions before sizing the canvas --
    // `getDisplayMedia` doesn't guarantee metadata is ready synchronously.
    await video.onLoadedMetadata.first;
    await video.play().toDart;

    final int fullWidth = video.videoWidth;
    final int fullHeight = video.videoHeight;
    if (fullWidth == 0 || fullHeight == 0) {
      throw MathPadWebRecordingException(
        'The shared source reported no video dimensions -- try sharing again.',
      );
    }

    final Rectangle<int>? effectiveCrop = _resolveCropRect(screenStream, cropRect, fullWidth, fullHeight);
    final int width = effectiveCrop?.width ?? fullWidth;
    final int height = effectiveCrop?.height ?? fullHeight;

    if (includeCamera) {
      await _startCamera(mediaDevices);
    }

    final web.HTMLCanvasElement canvas = web.HTMLCanvasElement()
      ..width = width
      ..height = height;
    _canvas = canvas;
    final web.CanvasRenderingContext2D ctx =
        canvas.getContext('2d') as web.CanvasRenderingContext2D;

    _drawLoopActive = true;
    void drawFrame(num _) {
      if (!_drawLoopActive) return;
      if (effectiveCrop != null) {
        ctx.drawImage(
          video,
          effectiveCrop.left,
          effectiveCrop.top,
          effectiveCrop.width,
          effectiveCrop.height,
          0,
          0,
          width,
          height,
        );
      } else {
        ctx.drawImage(video, 0, 0);
      }
      _drawCameraOverlay(ctx, width, height);
      web.window.requestAnimationFrame(drawFrame.toJS);
    }
    web.window.requestAnimationFrame(drawFrame.toJS);

    final web.MediaStream canvasStream = canvas.captureStream(fps);
    _canvasStream = canvasStream;

    final String? mimeType = _pickSupportedMimeType();
    if (mimeType == null) {
      throw MathPadWebRecordingException(
        'This browser has no supported video recording format available.',
      );
    }

    _chunks.clear();
    final web.MediaRecorder recorder = web.MediaRecorder(
      canvasStream,
      web.MediaRecorderOptions(mimeType: mimeType),
    );
    recorder.ondataavailable = ((web.Event e) {
      final web.Blob data = (e as web.BlobEvent).data;
      if (data.size > 0) _chunks.add(data);
    }).toJS;
    recorder.onstop = ((web.Event _) {
      final String finalType = mimeType.split(';').first;
      final web.Blob finalBlob = web.Blob(
        _chunks.toJS,
        web.BlobPropertyBag(type: finalType),
      );
      _stopCompleter?.complete(finalBlob);
    }).toJS;
    _recorder = recorder;
    recorder.start();
  }

  /// Best-effort camera start -- a failure here (permission denied, no
  /// camera, unsupported) only ever costs the camera overlay, never the
  /// recording itself, matching every native platform's compositor in
  /// this app.
  Future<void> _startCamera(web.MediaDevices mediaDevices) async {
    try {
      final web.MediaStream camStream = await mediaDevices
          .getUserMedia(web.MediaStreamConstraints(video: true.toJS, audio: false.toJS))
          .toDart;
      final web.HTMLVideoElement camVideo = web.HTMLVideoElement()
        ..srcObject = camStream
        ..muted = true
        ..autoplay = true;
      await camVideo.onLoadedMetadata.first;
      await camVideo.play().toDart;
      _cameraStream = camStream;
      _cameraVideo = camVideo;
    } catch (_) {
      _cameraStream = null;
      _cameraVideo = null;
    }
  }

  /// Draws the cropped/scaled/bordered camera PIP box on top of whatever
  /// was already drawn this frame -- matches the exact spec (crop=ih:ih,
  /// scale to 240x240, white border, top-right 24px inset) every other
  /// camera-overlay path in this app uses. No-op if no camera is active.
  void _drawCameraOverlay(web.CanvasRenderingContext2D ctx, int canvasWidth, int canvasHeight) {
    final web.HTMLVideoElement? camVideo = _cameraVideo;
    if (camVideo == null || camVideo.videoWidth == 0) return;

    final double camW = camVideo.videoWidth.toDouble();
    final double camH = camVideo.videoHeight.toDouble();
    final double cropSize = camW < camH ? camW : camH;
    final double camCropX = (camW - cropSize) / 2;
    const double boxSize = 240, inset = 24;
    final double destX = canvasWidth - inset - boxSize;
    final double destY = inset;

    ctx.drawImage(camVideo, camCropX, 0, cropSize, cropSize, destX, destY, boxSize, boxSize);
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.9)'.toJS;
    ctx.lineWidth = 4;
    ctx.strokeRect(destX, destY, boxSize, boxSize);
  }

  /// See this file's header comment ("CROP-TO-CANVAS") for the full
  /// reasoning -- only returns [candidate] back out (clamped to the
  /// captured frame's own bounds, in case it was measured a moment before/
  /// after a resize) when the shared source's `displaySurface` reports
  /// `'browser'`; null (meaning "don't crop") in every other case,
  /// including any failure to read that setting at all.
  Rectangle<int>? _resolveCropRect(
    web.MediaStream stream,
    Rectangle<int>? candidate,
    int fullWidth,
    int fullHeight,
  ) {
    if (candidate == null || candidate.width <= 0 || candidate.height <= 0) return null;
    try {
      final JSArray<web.MediaStreamTrack> tracks = stream.getVideoTracks();
      if (tracks.toDart.isEmpty) return null;
      final web.MediaTrackSettings settings = tracks.toDart.first.getSettings();
      final String? displaySurface = (settings as _DisplaySurfaceSettings).displaySurface?.toDart;
      if (displaySurface != 'browser') return null;
    } catch (_) {
      return null;
    }

    final int x0 = candidate.left.clamp(0, fullWidth);
    final int y0 = candidate.top.clamp(0, fullHeight);
    final int x1 = (candidate.left + candidate.width).clamp(x0, fullWidth);
    final int y1 = (candidate.top + candidate.height).clamp(y0, fullHeight);
    if (x1 <= x0 || y1 <= y0) return null;
    return Rectangle<int>(x0, y0, x1 - x0, y1 - y0);
  }

  /// Stops capture/compositing/encoding and immediately triggers a
  /// browser download of the result -- the simplest of the three output
  /// strategies discussed in the design (download / IndexedDB / backend
  /// upload); see this file's header comment. [filenameWithoutExtension]
  /// gets the right extension appended automatically based on the actual
  /// codec `MediaRecorder` used (`.webm` or `.mp4`).
  ///
  /// Deliberately doesn't expose the underlying `Blob` in its signature --
  /// keeping every `package:web` type internal to this file is what lets
  /// `mathpad_web_recording_service.dart` (the conditional-import barrel)
  /// give non-web platforms a stub with an identical public API without
  /// THAT file ever needing to reference `package:web` at all.
  Future<void> stopAndDownload({String filenameWithoutExtension = 'MathPad_recording'}) async {
    final web.Blob blob = await _stop();
    final String extension = blob.type.contains('mp4') ? 'mp4' : 'webm';
    _triggerDownload(blob, '$filenameWithoutExtension.$extension');
  }

  Future<web.Blob> _stop() async {
    final web.MediaRecorder? recorder = _recorder;
    if (recorder == null) {
      throw MathPadWebRecordingException('Not currently recording.');
    }
    _drawLoopActive = false;
    final Completer<web.Blob> completer = Completer<web.Blob>();
    _stopCompleter = completer;
    recorder.stop();
    final web.Blob result = await completer.future;
    _releaseResources();
    return result;
  }

  /// Stops every active track and tears down internal state WITHOUT
  /// waiting for/processing a final encoded blob -- for when the tutor
  /// navigates away mid-recording rather than pressing Stop. Deliberately
  /// does NOT try to salvage a partial download (MediaRecorder's `onstop`
  /// may not fire cleanly during a widget-tree teardown, and forcing a
  /// surprise file download during navigation would be a confusing UX) --
  /// this just makes sure the screen-share/camera indicators in the
  /// browser chrome actually turn off and no resources leak, accepting
  /// the partial recording is lost. Safe to call even when not recording.
  void cancelSync() {
    if (!isRecording && _screenStream == null) return;
    _drawLoopActive = false;
    try {
      _recorder?.stop();
    } catch (_) {}
    _releaseResources();
  }

  void _releaseResources() {
    for (final web.MediaStreamTrack track in _screenStream?.getTracks().toDart ?? const <web.MediaStreamTrack>[]) {
      track.stop();
    }
    for (final web.MediaStreamTrack track in _canvasStream?.getTracks().toDart ?? const <web.MediaStreamTrack>[]) {
      track.stop();
    }
    for (final web.MediaStreamTrack track in _cameraStream?.getTracks().toDart ?? const <web.MediaStreamTrack>[]) {
      track.stop();
    }
    _recorder = null;
    _screenStream = null;
    _canvasStream = null;
    _cameraStream = null;
    _screenVideo = null;
    _cameraVideo = null;
    _canvas = null;
    _stopCompleter = null;
  }

  static void _triggerDownload(web.Blob blob, String filename) {
    final String url = web.URL.createObjectURL(blob);
    final web.HTMLAnchorElement anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = filename
      ..style.display = 'none';
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
  }

  /// `MediaRecorder` needs an explicit, browser-supported mimeType --
  /// there's no universal default. VP9/WebM is the most broadly supported
  /// combination across Chromium/Firefox; H.264/MP4 support varies
  /// significantly (notably absent in many non-Safari browsers as a
  /// MediaRecorder target, even where it's supported for playback).
  static String? _pickSupportedMimeType() {
    const List<String> candidates = [
      'video/webm;codecs=vp9',
      'video/webm;codecs=vp8',
      'video/webm',
      'video/mp4',
    ];
    for (final String candidate in candidates) {
      if (web.MediaRecorder.isTypeSupported(candidate)) return candidate;
    }
    return null;
  }
}
