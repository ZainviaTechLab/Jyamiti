import 'dart:math' show pi;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'instrument_handle.dart';
import 'instrument_models.dart';

/// A draggable, rotatable cm ruler used as a straight-edge for drawing.
///
/// This widget is purely visual (the ruler body, tick marks, and handle
/// icons) — dragging the move/rotate handles is handled centrally by the
/// canvas's own gesture detector (see `_MathsPadWidgetState`'s
/// `_hitTestInstrumentHandles`/`_applyInstrumentDrag`), which already has a
/// correct screen->world conversion for the whole canvas. Only the "remove"
/// button is a simple local tap, which doesn't need that conversion.
class RulerWidget extends StatelessWidget {
  final RulerState state;
  final bool isDark;
  final ui.Image? logoImage;

  const RulerWidget({
    super.key,
    required this.state,
    required this.isDark,
    this.logoImage,
  });

  @override
  Widget build(BuildContext context) {
    final handles = state.handleWorldPositions();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IgnorePointer(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CustomPaint(
                size: Size.infinite,
                painter: _RulerPainter(
                  state: state,
                  isDark: isDark,
                  logoImage: logoImage,
                ),
              ),
              _visualHandle(handles['rotate']!, InstrumentHandleRole.rotate),
              _visualPencil(handles['pencil']!, state.pencilArmed),
            ],
          ),
        ),
      ],
    );
  }

  Widget _visualHandle(Offset worldPos, InstrumentHandleRole role) {
    const r = InstrumentHandle.size / 2;
    return Positioned(
      left: worldPos.dx - r,
      top: worldPos.dy - r,
      child: InstrumentHandle(role: role, tooltip: ''),
    );
  }

  // `Icons.edit_rounded`'s glyph rests tip-pointing up-right, not down-left
  // as first guessed (confirmed backwards -- flipped 180° from the
  // original `3*pi/4` estimate) -- same correction constant as
  // `ProtractorWidget`'s pencil (same icon).
  static const double _pencilIconTipAngle = -pi / 4;

  /// Rotates the pencil to point toward the ruler's drawing edge -- like a
  /// pencil actually braced against the ruler, tip touching the edge,
  /// shaft perpendicular to it -- instead of always sitting upright
  /// regardless of the ruler's own rotation. Fixed relative to the ruler
  /// (only changes when the whole ruler is rotated via its rotate handle),
  /// unlike the Protractor's pencil, whose angle also varies as it's
  /// dragged around the arc.
  Widget _visualPencil(Offset worldPos, bool armed) {
    const r = InstrumentHandle.size / 2;
    final double pointAngle = state.rotation - pi / 2;
    return Positioned(
      left: worldPos.dx - r,
      top: worldPos.dy - r,
      child: Transform.rotate(
        angle: pointAngle - _pencilIconTipAngle,
        child: InstrumentHandle(
          role: InstrumentHandleRole.pencil,
          tooltip: '',
          armed: armed,
        ),
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  final RulerState state;
  final bool isDark;
  final ui.Image? logoImage;

  _RulerPainter({required this.state, required this.isDark, this.logoImage});

  @override
  void paint(Canvas canvas, Size size) {
    final halfLen = state.lengthPx / 2;
    const double height = kRulerHalfHeight * 2;

    canvas.save();
    canvas.translate(state.pivot.dx, state.pivot.dy);
    canvas.rotate(state.rotation);

    final bodyRect = Rect.fromLTWH(
      -halfLen,
      -height / 2,
      state.lengthPx,
      height,
    );
    final bodyPaint = Paint()
      ..color = isDark
          ? const Color(0xFFCBB8F0).withOpacity(0.92)
          : const Color(0xFFD8CCF0).withOpacity(0.95);
    final borderPaint = Paint()
      ..color = const Color(0xFF6B46C1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawRect(bodyRect, bodyPaint);
    canvas.drawRect(bodyRect, borderPaint);

    // Tick marks, matching a real ruler's three tiers: every mm (shortest),
    // every half-cm/5mm (medium), every whole cm (tallest) -- only the
    // whole-cm marks are labeled (1, 2, 3, ...) along the full length.
    // Stepped in whole mm (not `cm += 0.1`) so float accumulation error
    // can't ever make a tick land just off a clean 5mm/10mm boundary.
    final tickPaint = Paint()
      ..color = const Color(0xFF3B0764)
      ..strokeWidth = 1;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    final totalCm = state.lengthCm;
    final int totalMm = (totalCm * 10).round();
    for (int mm = 0; mm <= totalMm; mm++) {
      final double cm = mm / 10;
      final x = -halfLen + cm * kPxPerCm;
      final bool isWholeCm = mm % 10 == 0;
      final bool isHalfCm = mm % 5 == 0;
      final double tickHeight = isWholeCm ? 20.0 : (isHalfCm ? 13.0 : 7.0);
      canvas.drawLine(
        Offset(x, -height / 2),
        Offset(x, -height / 2 + tickHeight),
        tickPaint,
      );
      if (isWholeCm) {
        textPainter.text = TextSpan(
          text: (mm ~/ 10).toString(),
          style: const TextStyle(
            color: Color(0xFF3B0764),
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(x - textPainter.width / 2, -height / 2 + tickHeight + 2),
        );
      }
    }

    // Small branding watermark, centered on the ruler body.
    if (logoImage != null) {
      const double logoSize = 20;
      final Rect dst = Rect.fromCenter(
        center: Offset.zero,
        width: logoSize,
        height: logoSize,
      );
      canvas.drawImageRect(
        logoImage!,
        Rect.fromLTWH(
          0,
          0,
          logoImage!.width.toDouble(),
          logoImage!.height.toDouble(),
        ),
        dst,
        Paint()..color = Colors.white.withOpacity(0.55),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RulerPainter oldDelegate) => true;
}
