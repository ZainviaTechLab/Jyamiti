// ============================================================================
// Renamed from mathpad_web_recording_service.dart -- imported conditionally
// now (see mathpad_web_recording_service.dart, the new barrel file) rather
// than directly, since package:web/dart:js_interop are web-specific;
// mathpad_web_recording_service_stub.dart is what every other platform gets
// instead, with the exact same public API (start/isRecording/
// stopAndDownload). Wired into mathpad.dart's toolbar as its own,
// web-only recording button (kIsWeb-gated) -- a wholly SEPARATE
// implementation from MathPadRecordingService, not a platform branch
// inside it. That file imports dart:io/dart:ffi throughout (real files,
// spawned ffmpeg processes, native FFI) -- none of which exist on web, so
// this couldn't be added there even as a branch. See the design
// discussion that led here for the full reasoning.
//
// Scope of this first slice, deliberately narrow (matches how every native
// platform's compositor in this app also shipped without camera/crop
// first, then grew): screen/tab capture only, no camera overlay, no crop
// to a specific element -- captures whatever the browser's picker was
// given. Composited on the MAIN thread via a plain
// requestAnimationFrame-driven canvas draw loop -- NOT yet off the thread
// Flutter's own web rendering runs on, unlike the Windows/macOS/Linux
// compositors. See "NOT YET OFF-THREAD" below for why, and the real
// (narrower-support) upgrade path.
//
// UNAVOIDABLE, BY BROWSER DESIGN -- not a bug to fix later:
//   `getDisplayMedia()` always shows the browser's native "choose a
//   window/tab/screen" picker, every time, with no way for any app to
//   skip it. `preferCurrentTab: true` (Chromium) biases the picker's
//   default toward this tab but the user can still pick something else --
//   this module doesn't try to detect or prevent that.
//
// NOT YET OFF-THREAD -- the real reason the other three platforms'
// compositors are smooth is that capture+composite+encode never touch the
// thread the UI/interaction runs on. The genuine web equivalent (Insertable
// Streams: `MediaStreamTrackProcessor` producing a transferable
// `ReadableStream<VideoFrame>`, composited on an `OffscreenCanvas` inside a
// Worker) exists, but has meaningfully narrower browser support (primarily
// Chromium; Firefox/Safari support has historically been partial/behind a
// flag) -- shipping something that silently doesn't work on a big chunk of
// browsers felt worse than being upfront that this first version accepts
// main-thread compositing. Worth revisiting once broader support lands, or
// if this app is fine targeting Chromium-based browsers specifically.
//
// UNVERIFIED IN THE BROWSER, but more verifiable than the native modules:
// `flutter build web` (pure Dart-to-JS/wasm compilation, no native
// toolchain needed) DOES compile-check this file's use of `package:web`'s
// generated bindings -- real compiler errors were found and fixed while
// writing this. What compiling clean can't confirm: whether the actual
// runtime behavior (permission flow, MediaRecorder codec support, frame
// timing) works correctly in a real browser -- that needs an actual
// browser, which I don't have here either.
//
// ============================================================================

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

class MathPadWebRecordingException implements Exception {
  MathPadWebRecordingException(this.message);
  final String message;
  @override
  String toString() => message;
}

class MathPadWebRecordingService {
  web.MediaStream? _screenStream;
  web.HTMLVideoElement? _screenVideo;
  web.HTMLCanvasElement? _canvas;
  web.MediaRecorder? _recorder;
  web.MediaStream? _canvasStream;
  final List<web.Blob> _chunks = [];
  bool _drawLoopActive = false;
  Completer<web.Blob>? _stopCompleter;

  bool get isRecording => _recorder != null;

  /// Shows the browser's screen/tab/window picker (see this file's header
  /// comment -- unavoidable, every time), then starts compositing the
  /// chosen source onto an internal canvas and encoding it via
  /// `MediaRecorder`. [fps] controls both the draw loop's target rate and
  /// the canvas capture stream's rate.
  ///
  /// Throws [MathPadWebRecordingException] if the user cancels the picker,
  /// the browser doesn't support the required APIs, or no codec
  /// `MediaRecorder` will accept could be found (see [_pickSupportedMimeType]).
  Future<void> start({int fps = 30}) async {
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

    final int width = video.videoWidth;
    final int height = video.videoHeight;
    if (width == 0 || height == 0) {
      throw MathPadWebRecordingException(
        'The shared source reported no video dimensions -- try sharing again.',
      );
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
      ctx.drawImage(video, 0, 0);
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

  /// Stops capture/compositing/encoding and immediately triggers a
  /// browser download of the result -- the simplest of the three output
  /// strategies discussed in the design (download / IndexedDB / backend
  /// upload); see this file's header comment. [filenameWithoutExtension]
  /// gets the right extension appended automatically based on the actual
  /// codec `MediaRecorder` used (`.webm` or `.mp4` -- see
  /// `_pickSupportedMimeType`).
  ///
  /// Deliberately doesn't expose the underlying `Blob` in its signature
  /// (unlike an earlier draft of this method) -- keeping every
  /// `package:web` type internal to this file is what lets
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

    for (final web.MediaStreamTrack track in _screenStream?.getTracks().toDart ?? <web.MediaStreamTrack>[].toJS.toDart) {
      track.stop();
    }
    for (final web.MediaStreamTrack track in _canvasStream?.getTracks().toDart ?? <web.MediaStreamTrack>[].toJS.toDart) {
      track.stop();
    }
    _recorder = null;
    _screenStream = null;
    _canvasStream = null;
    _screenVideo = null;
    _canvas = null;
    _stopCompleter = null;

    return result;
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
