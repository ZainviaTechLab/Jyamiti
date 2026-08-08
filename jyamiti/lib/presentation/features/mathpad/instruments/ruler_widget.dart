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
              _visualHandle(handles['move']!, InstrumentHandleRole.move),
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

  Widget _visualPencil(Offset worldPos, bool armed) {
    const r = InstrumentHandle.size / 2;
    return Positioned(
      left: worldPos.dx - r,
      top: worldPos.dy - r,
      child: InstrumentHandle(
        role: InstrumentHandleRole.pencil,
        tooltip: '',
        armed: armed,
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

    // Tick marks: minor every 0.5cm, major (taller) every whole cm --
    // every whole-cm mark is labeled (1, 2, 3, ...) along the full length.
    final tickPaint = Paint()
      ..color = const Color(0xFF3B0764)
      ..strokeWidth = 1;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    final totalCm = state.lengthCm;
    for (double cm = 0; cm <= totalCm; cm += 0.5) {
      final x = -halfLen + cm * kPxPerCm;
      final isMajor = cm % 1 == 0;
      final isLabeled = isMajor;
      final tickHeight = isLabeled ? 20.0 : 8.0;
      canvas.drawLine(
        Offset(x, -height / 2),
        Offset(x, -height / 2 + tickHeight),
        tickPaint,
      );
      if (isLabeled) {
        textPainter.text = TextSpan(
          text: cm.toInt().toString(),
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
