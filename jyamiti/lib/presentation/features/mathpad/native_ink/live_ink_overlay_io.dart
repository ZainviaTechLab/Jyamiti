import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show Color, Offset;

import 'package:flutter/services.dart';

/// Dart-side bridge to `windows/runner/live_ink_overlay.h`'s native,
/// low-latency overlay for the currently-being-drawn Pen stroke -- see
/// that file's doc comment for the full design. `isSupported` gates
/// everything to Windows only (this file also gets picked for non-web
/// platforms in general via the barrel's `dart.library.io` check, but the
/// actual native runner code only exists for Windows right now -- every
/// method below is a safe no-op on macOS/Linux/mobile via that runtime
/// check, exactly like the stub).
class LiveInkOverlay {
  LiveInkOverlay._() {
    if (isSupported) {
      _channel.setMethodCallHandler(_handleMethodCall);
    }
  }
  static final LiveInkOverlay instance = LiveInkOverlay._();

  static bool get isSupported => Platform.isWindows;

  static const MethodChannel _channel = MethodChannel(
    'jyamiti.com/live_ink_overlay',
  );

  /// Fired once per finished native-captured stroke, with the full point
  /// list already converted to canvas-local logical `Offset`s (same
  /// coordinate space `updateTransform`'s rect and `armStroke`'s `start`
  /// use) and a parallel pressure list. Set once, in `mathpad.dart`'s
  /// `initState`.
  void Function(List<Offset> points, List<double> pressures)? onStrokeComplete;

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onStrokeComplete') {
      final List<dynamic> flat = call.arguments as List<dynamic>;
      final List<Offset> points = [];
      final List<double> pressures = [];
      for (int i = 0; i + 2 < flat.length; i += 3) {
        points.add(
          Offset((flat[i] as num).toDouble(), (flat[i + 1] as num).toDouble()),
        );
        pressures.add((flat[i + 2] as num).toDouble());
      }
      onStrokeComplete?.call(points, pressures);
    }
    return null;
  }

  /// Repositions/resizes the (while idle, hidden) native overlay to
  /// exactly cover the canvas -- `left/top/width/height` are logical
  /// pixels relative to the app window's client area, the same space
  /// `_screenToWorld`/canvas-rect measurement already use. Cheap to call
  /// often (e.g. on every layout change); does nothing on an unsupported
  /// platform.
  void updateTransform({
    required double left,
    required double top,
    required double width,
    required double height,
  }) {
    if (!isSupported) return;
    unawaited(
      _channel.invokeMethod('updateTransform', {
        'clientLeft': left,
        'clientTop': top,
        'width': width,
        'height': height,
      }),
    );
  }

  /// Arms the native overlay for a new stroke, stealing Win32 pointer
  /// capture for the gesture already in progress. Returns false (do
  /// nothing further, fall back to normal Flutter-side drawing for this
  /// stroke) on an unsupported platform or if arming otherwise fails.
  Future<bool> armStroke({
    required Offset start,
    required double startPressure,
    required Color color,
    required double strokeWidthPx,
  }) async {
    if (!isSupported) return false;
    try {
      final bool? ok = await _channel.invokeMethod<bool>('armStroke', {
        'startX': start.dx,
        'startY': start.dy,
        'startPressure': startPressure,
        'argbColor': color.toARGB32(),
        'strokeWidthPx': strokeWidthPx,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Cancels an in-progress armed stroke WITHOUT firing
  /// `onStrokeComplete` -- e.g. the page/widget is being torn down
  /// mid-stroke.
  Future<void> cancelStroke() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('cancelStroke');
    } catch (_) {}
  }
}
