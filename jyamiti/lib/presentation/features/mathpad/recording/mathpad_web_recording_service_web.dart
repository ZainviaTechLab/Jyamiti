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
// OFF-THREAD PATH -- added after a real test surfaced the exact drawing
// stutter expected from main-thread compositing (see "MAIN-THREAD
// FALLBACK" below). Uses Insertable Streams (`MediaStreamTrackProcessor`
// turning each video track into a transferable `ReadableStream<VideoFrame>`)
// + an `OffscreenCanvas` composited inside web/mathpad_recording_worker.js
// (plain JavaScript, NOT Dart -- Flutter's web build only compiles
// lib/main.dart; anything under web/ is copied as a static asset with ZERO
// compile-time checking, meaning that file has had LESS verification than
// anything else in this app). The worker posts back one composited
// `ImageBitmap` per frame; this file's job on the main thread shrinks to
// just `drawImage`-ing whatever bitmap arrives onto the same
// `<canvas>` -- captureStream()/MediaRecorder (both main-thread-only APIs)
// are unchanged, still driven off that canvas exactly as before, so that
// already-compile-verified pipeline is reused as-is.
//
// `MediaStreamTrackProcessor` has meaningfully narrower browser support
// than getDisplayMedia/MediaRecorder themselves (primarily Chromium).
// Rather than an up-front feature check (there's no sufficiently simple,
// reliable way to ask that directly via package:web/dart:js_interop's
// stable surface), `start()` just always ATTEMPTS the off-thread path
// and falls back to the ORIGINAL main-thread `requestAnimationFrame`
// draw loop (kept unchanged) on any failure -- constructing a
// nonexistent JS class throws a perfectly catchable exception either
// way, and this also catches setup failures on browsers that DO have
// the API but fail for some other reason, not just ones that lack it
// outright. `MediaStreamTrackProcessor` itself isn't in package:web's
// typed bindings either (a newer WebCodecs-adjacent API) -- declared
// here via small custom extension types, same technique
// `_DisplaySurfaceSettings` already used for `displaySurface`.
//
// MAIN-THREAD FALLBACK -- the original, first-shipped compositing path,
// unchanged: a plain `requestAnimationFrame`-driven canvas draw loop that
// runs on the SAME thread Flutter's own web rendering and pointer/stylus
// handling run on. A tutor testing this confirmed the exact drawing
// stutter that predicts -- the same class of problem `onCanvas` had on
// desktop, just reached via `<canvas>`/rAF instead of a widget rebuild.
//
// UNAVOIDABLE, BY BROWSER DESIGN -- not a bug to fix later:
//   `getDisplayMedia()` always shows the browser's native "choose a
//   window/tab/screen" picker, every time, with no way for any app to
//   skip it. `preferCurrentTab: true` (Chromium) biases the picker's
//   default toward this tab but the user can still pick something else.
//
// CROP-TO-CANVAS -- after getDisplayMedia resolves, the video track's own
// `getSettings()` is inspected for `displaySurface` ('browser' | 'window'
// | 'monitor') -- the crop rect mathpad.dart measured off the canvas
// widget's own RenderBox is only ever applied when it's 'browser',
// otherwise this falls back to capturing the full shared source, since
// there's no way to know for certain the user picked "this tab" and a
// wrong-source crop would be nonsensical.
//
// CAMERA OVERLAY -- same PIP spec every other camera-overlay path in this
// app uses (crop to square, scale to 240x240, white border, top-right
// 24px inset). Best-effort -- a getUserMedia failure only ever costs the
// overlay, never the recording, matching every native platform here.
//
// AUDIO -- added after the first several versions of this shipped
// completely silent (getDisplayMedia's own `audio` option was left
// false, and there was no separate microphone capture at all -- a real
// gap, not a deliberate choice, caught when asked directly "anything
// left to do here"). A dedicated microphone-only getUserMedia call
// (independent of the camera's, since a tutor might want narration
// without wanting their face on camera) runs FIRST, before the screen
// picker even appears -- matching MathPadRecordingService.start's own
// "check the mic before anything else" ordering on desktop. Unlike
// camera, a microphone failure IS fatal here (throws immediately,
// before ever showing the screen picker) -- this feature exists to
// capture narration; recording it silently would defeat the point
// rather than just be a lesser version of it, the same reasoning
// desktop's own mic-permission check already uses. The mic's audio
// track and the composited canvas's video track are combined into one
// fresh MediaStream right before MediaRecorder starts, since
// MediaRecorder only ever records the tracks on the ONE stream it's
// given.
//
// UNVERIFIED IN THE BROWSER, but more verifiable than the native modules
// (for the Dart parts): `flutter build web` compile-checks this file's
// `package:web` API usage, and real compiler errors were found and fixed
// while writing every part of this, including the off-thread path's
// speculative bindings. What compiling clean can't confirm: actual
// runtime behavior (whether MediaStreamTrackProcessor really behaves as
// expected, whether the worker script -- entirely unchecked -- actually
// runs, permission flow, codec support, frame timing) -- that needs a
// real browser, which I don't have.
// ============================================================================

import 'dart:async';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:web/web.dart' as web;

import 'mathpad_web_recording_service.dart';

class MathPadWebRecordingException implements Exception {
  MathPadWebRecordingException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// `DisplayMediaStreamOptions.preferCurrentTab` -- a Chromium-specific
/// addition, not in package:web's typed bindings, and (per real-world
/// testing) genuinely needed: without it, Chrome's tab picker excludes
/// the calling tab itself from the list by design (this app's own tab
/// never showed up, only every OTHER open tab). `implements
/// web.DisplayMediaStreamOptions` is what lets a value of this type be
/// passed anywhere the original type is expected (extension types can
/// implement other extension types over the same underlying JSObject).
extension type _DisplayMediaStreamOptionsPreferCurrentTab._(JSObject _)
    implements web.DisplayMediaStreamOptions {
  external factory _DisplayMediaStreamOptionsPreferCurrentTab({
    JSAny? video,
    JSAny? audio,
    JSBoolean? preferCurrentTab,
  });
}

/// Reads `MediaTrackSettings.displaySurface` -- not in package:web's typed
/// bindings (a newer/optional part of the Screen Capture spec) -- via a
/// small custom extension type over the same underlying JSObject, rather
/// than needing the older, now-discouraged `dart:js_util`.
extension type _DisplaySurfaceSettings._(JSObject _) implements JSObject {
  external JSString? get displaySurface;
}

/// `MediaStreamTrackProcessor` (Insertable Streams / WebCodecs-adjacent) --
/// also not in package:web's typed bindings. `readable` is a
/// `ReadableStream<VideoFrame>`, but package:web's `ReadableStream` isn't
/// itself generic, so it's just typed as `web.ReadableStream` here (the
/// worker script treats whatever it reads as a VideoFrame regardless).
extension type _MediaStreamTrackProcessor._(JSObject _) implements JSObject {
  external factory _MediaStreamTrackProcessor(_TrackProcessorInit init);
  external web.ReadableStream get readable;
}

extension type _TrackProcessorInit._(JSObject _) implements JSObject {
  external factory _TrackProcessorInit({web.MediaStreamTrack track});
}

extension type _WorkerStartMessage._(JSObject _) implements JSObject {
  external factory _WorkerStartMessage({
    String type,
    web.ReadableStream screenStream,
    web.ReadableStream? cameraStream,
    int outputWidth,
    int outputHeight,
    _WorkerCropRect? cropRect,
  });
}

extension type _WorkerCropRect._(JSObject _) implements JSObject {
  external factory _WorkerCropRect({num x, num y, num w, num h});
}

extension type _WorkerStopMessage._(JSObject _) implements JSObject {
  external factory _WorkerStopMessage({String type});
}

extension type _WorkerResponse._(JSObject _) implements JSObject {
  external String get type;
  external web.ImageBitmap? get bitmap;
  external String? get message;
}

class MathPadWebRecordingService {
  web.MediaStream? _screenStream;
  web.MediaStream? _cameraStream;
  web.MediaStream? _micStream;
  web.HTMLVideoElement? _screenVideo;
  web.HTMLVideoElement? _cameraVideo;
  web.MediaRecorder? _recorder;
  web.MediaStream? _canvasStream;
  web.Worker? _worker;
  final List<web.Blob> _chunks = [];
  bool _drawLoopActive = false;
  Completer<web.Blob>? _stopCompleter;

  bool get isRecording => _recorder != null;

  /// Starts recording with either:
  /// 1. [WebRecordingTarget.canvasOnly] -- records purely the whiteboard canvas (no toolbars, no screen picker)
  /// 2. [WebRecordingTarget.screenTab] -- records the chosen tab/window via `getDisplayMedia`
  Future<void> start({
    int fps = 30,
    bool includeCamera = false,
    Rectangle<int>? cropRect,
    WebRecordingTarget target = WebRecordingTarget.canvasOnly,
    int? canvasWidth,
    int? canvasHeight,
    Future<ui.Image?> Function()? captureCanvasFrame,
  }) async {
    if (isRecording) return;

    final web.MediaDevices mediaDevices = web.window.navigator.mediaDevices;

    try {
      _micStream = await mediaDevices
          .getUserMedia(web.MediaStreamConstraints(audio: true.toJS, video: false.toJS))
          .toDart;
    } catch (e) {
      throw MathPadWebRecordingException(
        'Microphone access is needed to record narration -- please allow '
        'microphone access and try again.',
      );
    }

    if (includeCamera) {
      await _startCamera(mediaDevices);
    }

    if (target == WebRecordingTarget.canvasOnly) {
      final int width = canvasWidth ?? cropRect?.width ?? 1920;
      final int height = canvasHeight ?? cropRect?.height ?? 1080;
      await _startCanvasOnly(
        width: width,
        height: height,
        fps: fps,
        includeCamera: includeCamera,
        captureCanvasFrame: captureCanvasFrame,
      );
      return;
    }

    late web.MediaStream screenStream;
    try {
      final web.DisplayMediaStreamOptions options = _DisplayMediaStreamOptionsPreferCurrentTab(
        video: true.toJS,
        audio: false.toJS,
        preferCurrentTab: true.toJS,
      );
      screenStream = await mediaDevices.getDisplayMedia(options).toDart;
    } catch (e) {
      throw MathPadWebRecordingException(
        'Screen sharing was cancelled or denied -- recording needs a '
        'window/tab/screen to be selected.',
      );
    }
    _screenStream = screenStream;

    final web.MediaStreamTrack screenTrack = screenStream.getVideoTracks().toDart.first;
    final web.MediaTrackSettings screenSettings = screenTrack.getSettings();
    final int fullWidth = screenSettings.width.toInt();
    final int fullHeight = screenSettings.height.toInt();
    if (fullWidth == 0 || fullHeight == 0) {
      throw MathPadWebRecordingException(
        'The shared source reported no video dimensions -- try sharing again.',
      );
    }

    final Rectangle<int>? effectiveCrop =
        _resolveCropRect(screenTrack, cropRect, fullWidth, fullHeight);
    final int width = effectiveCrop?.width ?? fullWidth;
    final int height = effectiveCrop?.height ?? fullHeight;

    final web.MediaStreamTrack? cameraTrack = _cameraStream?.getVideoTracks().toDart.isNotEmpty == true
        ? _cameraStream!.getVideoTracks().toDart.first
        : null;

    try {
      await _startOffThread(
        screenTrack: screenTrack,
        cameraTrack: cameraTrack,
        width: width,
        height: height,
        effectiveCrop: effectiveCrop,
        fps: fps,
      );
      return;
    } catch (_) {
      _worker?.terminate();
      _worker = null;
    }

    await _startMainThreadFallback(
      width: width,
      height: height,
      effectiveCrop: effectiveCrop,
      fps: fps,
    );
  }

  /// Pure whiteboard canvas recording path -- streams directly from an
  /// HTML5 `<canvas>` populated by [captureCanvasFrame] with zero toolbars and zero
  /// screen-share popups.
  Future<void> _startCanvasOnly({
    required int width,
    required int height,
    required int fps,
    required bool includeCamera,
    required Future<ui.Image?> Function()? captureCanvasFrame,
  }) async {
    final web.HTMLCanvasElement canvas = web.HTMLCanvasElement()
      ..width = width
      ..height = height;
    final web.CanvasRenderingContext2D ctx =
        canvas.getContext('2d') as web.CanvasRenderingContext2D;

    ctx.fillStyle = '#0F2B52'.toJS;
    ctx.fillRect(0, 0, width, height);

    await _finishSetupAndStartRecorder(canvas: canvas, fps: fps);

    _drawLoopActive = true;
    bool inFlight = false;

    final int intervalMs = (1000 / fps).round().clamp(16, 100);
    Timer.periodic(Duration(milliseconds: intervalMs), (timer) async {
      if (!_drawLoopActive) {
        timer.cancel();
        return;
      }
      if (inFlight) return;
      inFlight = true;
      try {
        if (captureCanvasFrame != null) {
          final ui.Image? image = await captureCanvasFrame();
          if (image != null) {
            final int imgW = image.width;
            final int imgH = image.height;
            final ByteData? byteData =
                await image.toByteData(format: ui.ImageByteFormat.rawRgba);
            image.dispose();
            if (byteData != null) {
              if (canvas.width != imgW || canvas.height != imgH) {
                canvas.width = imgW;
                canvas.height = imgH;
              }
              final Uint8ClampedList clamped =
                  byteData.buffer.asUint8ClampedList();
              final web.ImageData imgData =
                  web.ImageData(clamped.toJS, imgW, imgH.toJS);
              ctx.putImageData(imgData, 0, 0);
            }
          }
        }
        if (includeCamera) {
          _drawCameraOverlay(ctx, canvas.width, canvas.height);
        }
      } catch (_) {}
      inFlight = false;
    });
  }


  Future<void> _startOffThread({
    required web.MediaStreamTrack screenTrack,
    required web.MediaStreamTrack? cameraTrack,
    required int width,
    required int height,
    required Rectangle<int>? effectiveCrop,
    required int fps,
  }) async {
    final web.ReadableStream screenReadable =
        _MediaStreamTrackProcessor(_TrackProcessorInit(track: screenTrack)).readable;
    final web.ReadableStream? cameraReadable = cameraTrack != null
        ? _MediaStreamTrackProcessor(_TrackProcessorInit(track: cameraTrack)).readable
        : null;

    final web.HTMLCanvasElement canvas = web.HTMLCanvasElement()
      ..width = width
      ..height = height;
    final web.CanvasRenderingContext2D ctx =
        canvas.getContext('2d') as web.CanvasRenderingContext2D;

    final web.Worker worker = web.Worker('mathpad_recording_worker.js'.toJS);
    _worker = worker;
    worker.onmessage = ((web.MessageEvent e) {
      final _WorkerResponse response = e.data as _WorkerResponse;
      if (response.type == 'frame') {
        final web.ImageBitmap? bitmap = response.bitmap;
        if (bitmap != null) {
          ctx.drawImage(bitmap, 0, 0);
          bitmap.close();
        }
      }
      // 'error' responses are non-fatal by design here -- the worker
      // already stopped trying on its own read loop; the recording still
      // has whatever frames arrived before the error, and Stop still
      // works normally.
    }).toJS;

    final _WorkerStartMessage startMessage = _WorkerStartMessage(
      type: 'start',
      screenStream: screenReadable,
      cameraStream: cameraReadable,
      outputWidth: width,
      outputHeight: height,
      cropRect: effectiveCrop != null
          ? _WorkerCropRect(
              x: effectiveCrop.left,
              y: effectiveCrop.top,
              w: effectiveCrop.width,
              h: effectiveCrop.height,
            )
          : null,
    );
    final List<JSObject> transferList = [screenReadable, ?cameraReadable];
    worker.postMessage(startMessage, transferList.toJS);

    await _finishSetupAndStartRecorder(canvas: canvas, fps: fps);
  }

  /// Original, first-shipped compositing path -- a plain
  /// `requestAnimationFrame`-driven canvas draw loop, unchanged. See this
  /// file's header comment ("MAIN-THREAD FALLBACK") for why it still
  /// exists: browsers without Insertable Streams support fall back to
  /// this rather than not recording at all, accepting the drawing-stutter
  /// tradeoff a tutor already confirmed happens here.
  Future<void> _startMainThreadFallback({
    required int width,
    required int height,
    required Rectangle<int>? effectiveCrop,
    required int fps,
  }) async {
    final web.HTMLVideoElement video = _screenVideo ??= (web.HTMLVideoElement()
      ..srcObject = _screenStream
      ..muted = true
      ..autoplay = true);
    await video.onLoadedMetadata.first;
    await video.play().toDart;

    final web.HTMLCanvasElement canvas = web.HTMLCanvasElement()
      ..width = width
      ..height = height;
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

    await _finishSetupAndStartRecorder(canvas: canvas, fps: fps);
  }

  Future<void> _finishSetupAndStartRecorder({
    required web.HTMLCanvasElement canvas,
    required int fps,
  }) async {
    final web.MediaStream canvasStream = canvas.captureStream(fps);
    _canvasStream = canvasStream;

    // MediaRecorder records whatever tracks are on the ONE stream it's
    // given -- the canvas's own captureStream() only ever has video, and
    // the mic stream only ever has audio, so they're combined into a
    // fresh MediaStream here rather than trying to record two streams at
    // once (MediaRecorder doesn't support that).
    final List<web.MediaStreamTrack> recordingTracks = [
      ...canvasStream.getVideoTracks().toDart,
      ...?_micStream?.getAudioTracks().toDart,
    ];
    final web.MediaStream recordingStream = web.MediaStream(recordingTracks.toJS);

    final String? mimeType = _pickSupportedMimeType();
    if (mimeType == null) {
      throw MathPadWebRecordingException(
        'This browser has no supported video recording format available.',
      );
    }

    _chunks.clear();
    final web.MediaRecorder recorder = web.MediaRecorder(
      recordingStream,
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
  /// this app. Returns the camera's video track for the off-thread path
  /// to build its own `MediaStreamTrackProcessor` from, or null.
  Future<web.MediaStreamTrack?> _startCamera(web.MediaDevices mediaDevices) async {
    try {
      final web.MediaStream camStream = await mediaDevices
          .getUserMedia(web.MediaStreamConstraints(video: true.toJS, audio: false.toJS))
          .toDart;
      _cameraStream = camStream;
      final web.MediaStreamTrack track = camStream.getVideoTracks().toDart.first;
      // Only the main-thread fallback path needs a playing <video>
      // element (it reads frames via drawImage(video, ...)); the
      // off-thread path reads frames directly off the track via
      // MediaStreamTrackProcessor instead, so this is created lazily by
      // _drawCameraOverlay only when that fallback path actually runs.
      return track;
    } catch (_) {
      _cameraStream = null;
      return null;
    }
  }

  /// Draws the cropped/scaled/bordered camera PIP box on top of whatever
  /// was already drawn this frame -- main-thread fallback path only (the
  /// off-thread path does the equivalent compositing inside the worker).
  /// Matches the exact spec every other camera-overlay path in this app
  /// uses. No-op if no camera is active.
  void _drawCameraOverlay(web.CanvasRenderingContext2D ctx, int canvasWidth, int canvasHeight) {
    final web.MediaStream? camStream = _cameraStream;
    if (camStream == null) return;
    web.HTMLVideoElement? camVideo = _cameraVideo;
    if (camVideo == null) {
      camVideo = web.HTMLVideoElement()
        ..srcObject = camStream
        ..muted = true
        ..autoplay = true;
      unawaited(camVideo.play().toDart.catchError((_) => null));
      _cameraVideo = camVideo;
    }
    if (camVideo.videoWidth == 0) return;

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
    web.MediaStreamTrack screenTrack,
    Rectangle<int>? candidate,
    int fullWidth,
    int fullHeight,
  ) {
    if (candidate == null || candidate.width <= 0 || candidate.height <= 0) return null;
    try {
      final web.MediaTrackSettings settings = screenTrack.getSettings();
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

  /// Stops capture/compositing/encoding and returns the finished
  /// recording's raw bytes -- NOT an automatic download. The caller (see
  /// mathpad.dart's `_stopWebRecording`) saves these into
  /// `MathPadWebRecordingsStorageService` (IndexedDB) so the recording
  /// shows up in a list the tutor can come back to, with Download as a
  /// deliberate, later action from there -- not something sprung on them
  /// the instant they hit Stop.
  ///
  /// Deliberately doesn't expose the underlying `Blob` in its signature --
  /// keeping every `package:web` type internal to this file is what lets
  /// `mathpad_web_recording_service.dart` (the conditional-import barrel)
  /// give non-web platforms a stub with an identical public API without
  /// THAT file ever needing to reference `package:web` at all.
  /// [MathPadWebRecordingResult] is a plain Dart class for the same reason.
  Future<MathPadWebRecordingResult> stop() async {
    final web.MediaRecorder? recorder = _recorder;
    if (recorder == null) {
      throw MathPadWebRecordingException('Not currently recording.');
    }
    _drawLoopActive = false;
    _worker?.postMessage(_WorkerStopMessage(type: 'stop'));
    final Completer<web.Blob> completer = Completer<web.Blob>();
    _stopCompleter = completer;
    recorder.stop();
    final web.Blob blob = await completer.future;
    _releaseResources();

    final JSArrayBuffer arrayBuffer = await blob.arrayBuffer().toDart;
    final Uint8List bytes = arrayBuffer.toDart.asUint8List();
    final String extension = blob.type.contains('mp4') ? 'mp4' : 'webm';
    return MathPadWebRecordingResult(
      bytes: bytes,
      mimeType: blob.type,
      fileExtension: extension,
    );
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
    try {
      _worker?.postMessage(_WorkerStopMessage(type: 'stop'));
      _worker?.terminate();
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
    for (final web.MediaStreamTrack track in _micStream?.getTracks().toDart ?? const <web.MediaStreamTrack>[]) {
      track.stop();
    }
    _recorder = null;
    _screenStream = null;
    _canvasStream = null;
    _cameraStream = null;
    _micStream = null;
    _screenVideo = null;
    _cameraVideo = null;
    _worker = null;
    _stopCompleter = null;
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
