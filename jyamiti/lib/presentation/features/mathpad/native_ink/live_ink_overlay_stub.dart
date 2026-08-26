import 'dart:ui' show Color, Offset;

/// No-op stub for platforms without a native live-stroke overlay
/// implementation (web, and -- until built -- macOS/Linux/mobile).
/// `isSupported` is always false, so every caller always takes the
/// normal Flutter-side drawing path unconditionally; every method here
/// is inert. See `live_ink_overlay_io.dart` for the real Windows
/// implementation and `windows/runner/live_ink_overlay.h` for the native
/// side's full design.
class LiveInkOverlay {
  LiveInkOverlay._();
  static final LiveInkOverlay instance = LiveInkOverlay._();

  static bool get isSupported => false;

  void Function(List<Offset> points, List<double> pressures)? onStrokeComplete;

  void updateTransform({
    required double left,
    required double top,
    required double width,
    required double height,
  }) {}

  Future<bool> armStroke({
    required Offset start,
    required double startPressure,
    required Color color,
    required double strokeWidthPx,
  }) async => false;

  Future<void> cancelStroke() async {}
}
