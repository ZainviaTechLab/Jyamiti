import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android-only bridge to `androidx.input.motionprediction`'s
/// `MotionEventPredictor`, fed from `MainActivity.kt`'s `dispatchTouchEvent`.
///
/// The native side is a read-only observer on the same raw touch stream
/// Flutter's own embedding already processes for every event -- it never
/// intercepts or consumes a touch, so Flutter's normal pointer/gesture
/// pipeline is completely unaffected by it.
///
/// It forwards a predicted look-ahead point as a `(dx, dy)` DELTA, in
/// logical pixels, from the most recent real touch sample -- not an
/// absolute position. The native side has no notion of where a Flutter
/// canvas widget sits within the widget tree (it only sees raw
/// activity-window coordinates), so callers must add this delta onto their
/// own last known real point (converted into whatever coordinate space
/// they track, e.g. dividing by a canvas's zoom `scale`) rather than
/// treating it as a position in their own coordinate space directly.
///
/// Only ever active for an actual stylus (`MotionEvent.TOOL_TYPE_STYLUS`)
/// -- mouse/touch/trackpad users get zero native-side overhead, matching
/// the same "real hardware pressure only" gating `mathpad.dart` already
/// uses for `_lastPencilStylusPressure`.
class StylusPredictionService {
  StylusPredictionService._();
  static final StylusPredictionService instance = StylusPredictionService._();

  static const MethodChannel _channel = MethodChannel(
    'jyamiti.mathpad/stylus_prediction',
  );

  /// The latest predicted `(dx, dy)` delta, in logical pixels, or null.
  /// This just relays whatever native last sent -- it does NOT track
  /// whether a caller has already consumed/applied it, so a caller that
  /// wants "only react to a genuinely new value" should compare against
  /// its own last-seen delta, not rely on this being reset to null.
  final ValueNotifier<Offset?> predictedDelta = ValueNotifier<Offset?>(null);

  bool _initialized = false;

  /// Safe to call from multiple widgets/multiple times -- only the first
  /// call actually registers the channel handler.
  void ensureInitialized() {
    if (_initialized || kIsWeb || !Platform.isAndroid) return;
    _initialized = true;
    _channel.setMethodCallHandler(_onMethodCall);
  }

  Future<void> _onMethodCall(MethodCall call) async {
    if (call.method != 'predictedDelta') return;
    final args = call.arguments as Map<Object?, Object?>;
    final double dx = (args['dx'] as num).toDouble();
    final double dy = (args['dy'] as num).toDouble();
    predictedDelta.value = Offset(dx, dy);
  }
}
