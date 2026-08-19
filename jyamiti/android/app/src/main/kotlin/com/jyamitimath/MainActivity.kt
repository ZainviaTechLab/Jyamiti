package com.jyamitimath

import android.view.MotionEvent
import androidx.input.motionprediction.MotionEventPredictor
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val STYLUS_PREDICTION_CHANNEL = "jyamiti.mathpad/stylus_prediction"

        // Ignore an implausibly small movement between two real samples --
        // requesting a prediction from a near-stationary pen produces noisy,
        // not-actually-useful output.
        private const val MIN_MOVE_PX_FOR_PREDICTION = 0.5f
    }

    // Forwards a short look-ahead point to Dart while drawing with an actual
    // stylus, to reduce perceived latency on the MathPad Pen tool -- see
    // `StylusPredictionService` (Dart side) for the full contract. This is a
    // read-only observer on the same raw touch stream Flutter's own
    // embedding already processes via `super.dispatchTouchEvent`: it never
    // consumes/intercepts an event, so Flutter's normal pointer/gesture
    // pipeline is completely unaffected.
    private var stylusPredictionChannel: MethodChannel? = null
    private var motionEventPredictor: MotionEventPredictor? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        stylusPredictionChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            STYLUS_PREDICTION_CHANNEL,
        )
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        // Only worth predicting for an actual pressure/tilt-capable stylus
        // (never mouse/touch/trackpad -- zero overhead for those), and only
        // for a single-pointer interaction, matching the app's own "2+
        // fingers = pan/zoom, not drawing" rule.
        if (event.pointerCount == 1 && event.getToolType(0) == MotionEvent.TOOL_TYPE_STYLUS) {
            val predictor = motionEventPredictor ?: MotionEventPredictor.newInstance(
                window.decorView,
            ).also { motionEventPredictor = it }

            predictor.record(event)

            if (event.actionMasked == MotionEvent.ACTION_MOVE) {
                val predicted = predictor.predict()
                if (predicted != null) {
                    val dxPx = predicted.x - event.x
                    val dyPx = predicted.y - event.y
                    if (Math.hypot(dxPx.toDouble(), dyPx.toDouble()) >= MIN_MOVE_PX_FOR_PREDICTION) {
                        // Flutter's own coordinate space (`PointerEvent.localPosition`,
                        // and everything mathpad.dart computes from it) is in
                        // LOGICAL pixels, while raw MotionEvent x/y are physical
                        // pixels -- convert before handing off.
                        val density = resources.displayMetrics.density
                        stylusPredictionChannel?.invokeMethod(
                            "predictedDelta",
                            mapOf(
                                "dx" to (dxPx / density).toDouble(),
                                "dy" to (dyPx / density).toDouble(),
                            ),
                        )
                    }
                    predicted.recycle()
                }
            }
        }

        return super.dispatchTouchEvent(event)
    }
}
