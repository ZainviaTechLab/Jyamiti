import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'instrument_handle.dart';
import 'instrument_models.dart';

/// A draggable, rotatable, resizable protractor (0-180 degree semicircle).
/// Its flat (diameter) edge also acts as a straight-edge for snapped
/// line drawing (see [ProtractorState.strokeableEdges]).
///
/// Purely visual — dragging the move/rotate/resize handles is handled
/// centrally by the canvas's own gesture detector (see
/// `_MathsPadWidgetState`'s `_hitTestInstrumentHandles`/`_applyInstrumentDrag`).
/// Only "remove" is a simple local tap.
class ProtractorWidget extends StatelessWidget {
  final ProtractorState state;
  final bool isDark;
  final ui.Image? logoImage;
  final VoidCallback onRemove;

  const ProtractorWidget({
    super.key,
    required this.state,
    required this.isDark,
    this.logoImage,
    required this.onRemove,
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
                painter: _ProtractorPainter(
                  state: state,
                  isDark: isDark,
                  logoImage: logoImage,
                ),
              ),
              _visualHandle(handles['move']!, InstrumentHandleRole.move),
              _visualHandle(handles['rotate']!, InstrumentHandleRole.rotate),
              _visualHandle(handles['resize']!, InstrumentHandleRole.resize),
            ],
          ),
        ),
        _tapHandle(
          handles['remove']!,
          InstrumentHandleRole.remove,
          'Remove Protractor',
          onRemove,
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

  Widget _tapHandle(
    Offset worldPos,
    InstrumentHandleRole role,
    String tooltip,
    VoidCallback onTap,
  ) {
    const r = InstrumentHandle.size / 2;
    return Positioned(
      left: worldPos.dx - r,
      top: worldPos.dy - r,
      child: InstrumentHandle(role: role, tooltip: tooltip, onTap: onTap),
    );
  }
}

class _ProtractorPainter extends CustomPainter {
  final ProtractorState state;
  final bool isDark;
  final ui.Image? logoImage;

  _ProtractorPainter({
    required this.state,
    required this.isDark,
    this.logoImage,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = state.radius;

    canvas.save();
    canvas.translate(state.pivot.dx, state.pivot.dy);
    canvas.rotate(state.rotation);

    // Semicircle bulges toward local -y (visually "up" at rotation 0),
    // flat edge lies along the local x-axis through the pivot.
    final bodyPath = Path()
      ..moveTo(-r, 0)
      ..arcTo(Rect.fromCircle(center: Offset.zero, radius: r), pi, pi, false)
      ..lineTo(r, 0)
      ..close();

    final bodyPaint = Paint()
      ..color = isDark
          ? const Color(0xFFF5F0DC).withOpacity(0.9)
          : const Color(0xFFF7F3E3).withOpacity(0.95);
    final borderPaint = Paint()
      ..color = const Color(0xFF78716C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawPath(bodyPath, bodyPaint);
    canvas.drawPath(bodyPath, borderPaint);

    // Radial angle guide lines from the center out to the rim, every 10deg,
    // so a drawn line can be visually aligned against a labeled angle.
    final radialPaint = Paint()
      ..color = const Color(0xFF78716C).withOpacity(0.35)
      ..strokeWidth = 1;
    for (int deg = 0; deg <= 180; deg += 10) {
      final theta = pi - (deg * pi / 180);
      final rimPt = Offset(cos(theta) * r, -sin(theta) * r);
      canvas.drawLine(Offset.zero, rimPt, radialPaint);
    }

    final tickPaint = Paint()
      ..color = const Color(0xFF44403C)
      ..strokeWidth = 1;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    // 0deg at local (+r, 0) sweeping to 180deg at local (-r, 0), through -y.
    for (int deg = 0; deg <= 180; deg++) {
      final theta = pi - (deg * pi / 180); // 0 -> pi, 180 -> 0
      final isMajor = deg % 10 == 0;
      final isMinor5 = deg % 5 == 0;
      final outerPt = Offset(cos(theta) * r, -sin(theta) * r);
      final tickLen = isMajor ? 14.0 : (isMinor5 ? 9.0 : 5.0);
      final innerPt = Offset(
        cos(theta) * (r - tickLen),
        -sin(theta) * (r - tickLen),
      );
      canvas.drawLine(outerPt, innerPt, tickPaint);

      if (isMajor) {
        // Real protractors carry two readings at every major tick so you can
        // measure from either direction: an outer scale (0->180) and an
        // inner scale (180->0), stacked one above the other.
        final outerLabelPt = Offset(
          cos(theta) * (r - 22),
          -sin(theta) * (r - 22),
        );
        final innerLabelPt = Offset(
          cos(theta) * (r - 40),
          -sin(theta) * (r - 40),
        );

        textPainter.text = TextSpan(
          text: '$deg',
          style: const TextStyle(
            color: Color(0xFF292524),
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          outerLabelPt - Offset(textPainter.width / 2, textPainter.height / 2),
        );

        textPainter.text = TextSpan(
          text: '${180 - deg}',
          style: const TextStyle(
            color: Color(0xFF9A3412),
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          innerLabelPt - Offset(textPainter.width / 2, textPainter.height / 2),
        );
      }
    }

    // Small branding watermark, centered in the body below the pivot.
    if (logoImage != null) {
      final double logoSize = min(22.0, r * 0.35);
      final Rect dst = Rect.fromCenter(
        center: Offset(0, -r * 0.5),
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
        Paint()..color = Colors.white.withOpacity(0.5),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ProtractorPainter oldDelegate) => true;
}
