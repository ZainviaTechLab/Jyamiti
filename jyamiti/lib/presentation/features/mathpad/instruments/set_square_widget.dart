import 'package:flutter/material.dart';
import 'instrument_handle.dart';
import 'instrument_models.dart';

/// A draggable, rotatable, resizable set-square (45-45-90 or 30-60-90
/// triangle ruler). Every edge is a usable straight-edge for snapped line
/// drawing (see [SetSquareState.strokeableEdges]).
///
/// Purely visual — dragging the move/rotate/resize handles is handled
/// centrally by the canvas's own gesture detector (see
/// `_MathsPadWidgetState`'s `_hitTestInstrumentHandles`/`_applyInstrumentDrag`).
/// Only "remove" is a simple local tap.
class SetSquareWidget extends StatelessWidget {
  final SetSquareState state;
  final bool isDark;
  final VoidCallback onRemove;

  const SetSquareWidget({
    super.key,
    required this.state,
    required this.isDark,
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
                painter: _SetSquarePainter(state: state, isDark: isDark),
              ),
              _visualHandle(handles['move']!, InstrumentHandleRole.move),
              _visualHandle(handles['rotate']!, InstrumentHandleRole.rotate),
              _visualHandle(handles['resize']!, InstrumentHandleRole.resize),
              _visualPencil(handles['pencil']!, state.pencilArmed),
            ],
          ),
        ),
        _tapHandle(
          handles['remove']!,
          InstrumentHandleRole.remove,
          'Remove Set Square',
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

class _SetSquarePainter extends CustomPainter {
  final SetSquareState state;
  final bool isDark;

  _SetSquarePainter({required this.state, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final verts = state.localVertices();

    canvas.save();
    canvas.translate(state.pivot.dx, state.pivot.dy);
    canvas.rotate(state.rotation);

    final path = Path()
      ..moveTo(verts[0].dx, verts[0].dy)
      ..lineTo(verts[1].dx, verts[1].dy)
      ..lineTo(verts[2].dx, verts[2].dy)
      ..close();

    final bodyPaint = Paint()
      ..color = isDark
          ? const Color(0xFFBFDBFE).withOpacity(0.55)
          : const Color(0xFFBFDBFE).withOpacity(0.75);
    final borderPaint = Paint()
      ..color = const Color(0xFF1D4ED8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawPath(path, bodyPaint);
    canvas.drawPath(path, borderPaint);

    // Tick marks along the base leg (v0 -> v1), the ruled measuring edge,
    // matching a real set-square/triangle ruler.
    final tickPaint = Paint()
      ..color = const Color(0xFF1E3A8A)
      ..strokeWidth = 1;
    final base = verts[1] - verts[0];
    final baseLen = base.distance;
    final baseDir = base / baseLen;
    // Points away from the triangle's interior (v2 sits on the +normal
    // side of the base, so ticks are drawn on the opposite side).
    final normal = Offset(baseDir.dy, -baseDir.dx);
    const double cmPx = kPxPerCm;
    for (double d = 0; d <= baseLen; d += cmPx) {
      final tickBase = verts[0] + baseDir * d;
      final isMajor = ((d / cmPx).round() % 5 == 0);
      final tickLen = isMajor ? 10.0 : 6.0;
      canvas.drawLine(tickBase, tickBase + normal * tickLen, tickPaint);
    }

    // Degree labels at each corner.
    final labels = state.kind == SetSquareKind.fortyFive
        ? const ['90°', '45°', '45°']
        : const ['90°', '60°', '30°'];
    final centroid = Offset(
      (verts[0].dx + verts[1].dx + verts[2].dx) / 3,
      (verts[0].dy + verts[1].dy + verts[2].dy) / 3,
    );
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    for (int i = 0; i < 3; i++) {
      final towardCenter = centroid - verts[i];
      final len = towardCenter.distance == 0 ? 1.0 : towardCenter.distance;
      final labelPos = verts[i] + towardCenter / len * 22;
      textPainter.text = TextSpan(
        text: labels[i],
        style: const TextStyle(
          color: Color(0xFF1E3A8A),
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        labelPos - Offset(textPainter.width / 2, textPainter.height / 2),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SetSquarePainter oldDelegate) => true;
}
