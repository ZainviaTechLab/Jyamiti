import 'dart:math';
import 'package:flutter/material.dart';
import 'instrument_handle.dart';
import 'instrument_models.dart';

/// A compass with a fixed pivot leg and a hinged pencil arm — drawn as a
/// real drafting compass: two legs meeting at a top hinge/joint, splaying
/// apart as the radius grows.
///
/// Purely visual for the pivot/hinge/tip legs — dragging them is handled
/// centrally by the canvas's own gesture detector (see
/// `_MathsPadWidgetState`'s `_hitTestInstrumentHandles`/`_applyInstrumentDrag`
/// /`_updateCompassAngle`), which already has a correct screen->world
/// conversion for the whole canvas (locking, arc-tracing and committing the
/// finished arc into the canvas's permanent line list all happen there too).
/// The lock/refresh/remove badge buttons are simple local taps.
class CompassWidget extends StatelessWidget {
  final CompassState state;
  final bool isDark;
  final VoidCallback onToggleLock;
  final VoidCallback onRefresh;
  final VoidCallback onRemove;

  const CompassWidget({
    super.key,
    required this.state,
    required this.isDark,
    required this.onToggleLock,
    required this.onRefresh,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final tip = state.tipWorldPosition;
    final hinge = state.hingePoint;
    final badgeAnchor = tip + const Offset(22, -14);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IgnorePointer(
          child: CustomPaint(
            size: Size.infinite,
            painter: _CompassPainter(state: state, hinge: hinge),
          ),
        ),
        IgnorePointer(
          child: Positioned(
            left: hinge.dx - InstrumentHandle.size / 2,
            top: hinge.dy - InstrumentHandle.size / 2,
            child: const InstrumentHandle(
              role: InstrumentHandleRole.rotate,
              tooltip: '',
            ),
          ),
        ),

        Positioned(
          left: badgeAnchor.dx,
          top: badgeAnchor.dy,
          child: _CompassBadge(
            state: state,
            onToggleLock: onToggleLock,
            onRefresh: onRefresh,
            onRemove: onRemove,
          ),
        ),
      ],
    );
  }
}

class _CompassBadge extends StatelessWidget {
  final CompassState state;
  final VoidCallback onToggleLock;
  final VoidCallback onRefresh;
  final VoidCallback onRemove;

  const _CompassBadge({
    required this.state,
    required this.onToggleLock,
    required this.onRefresh,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${state.radiusCm.toStringAsFixed(1)} cm',
              style: const TextStyle(
                color: Color(0xFF1E293B),
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggleLock,
              child: Icon(
                state.locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                size: 18,
                color: state.locked ? const Color(0xFF22C55E) : Colors.grey,
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onRefresh,
              child: const Icon(
                Icons.refresh_rounded,
                size: 18,
                color: Colors.grey,
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onRemove,
              child: const Icon(
                Icons.close_rounded,
                size: 18,
                color: Color(0xFFEF4444),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  final CompassState state;
  final Offset hinge;

  _CompassPainter({required this.state, required this.hinge});

  @override
  void paint(Canvas canvas, Size size) {
    final Offset pivot = state.pivot;
    final Offset tip = state.tipWorldPosition;

    // Two tapered metal legs meeting at the hinge -- wide near the joint,
    // narrowing toward the far end, like a real drafting compass's arms.
    _drawLeg(canvas, from: hinge, to: pivot, isNeedleLeg: true);
    _drawLeg(canvas, from: hinge, to: tip, isNeedleLeg: false);

    _drawNeedleTip(canvas, pivot, hinge);
    _drawPencilTip(canvas, tip, hinge);
    _drawHinge(canvas);

    if (state.locked && state.tracedArcPoints.length > 1) {
      final arcPaint = Paint()
        ..color = Colors.black87
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      final path = Path()
        ..moveTo(state.tracedArcPoints.first.dx, state.tracedArcPoints.first.dy);
      for (final p in state.tracedArcPoints.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, arcPaint);
    }
  }

  /// Tapered metal leg -- a filled quadrilateral, wide at the hinge end and
  /// narrowing toward the tip end (stopping a little short of the very tip,
  /// leaving room for the needle/pencil shape drawn separately), shaded with
  /// a brushed-steel gradient across its width so it reads as a solid metal
  /// arm rather than a flat stroked line.
  void _drawLeg(
    Canvas canvas, {
    required Offset from,
    required Offset to,
    required bool isNeedleLeg,
  }) {
    final Offset dir = to - from;
    final double len = dir.distance;
    if (len < 1) return;
    final Offset unit = dir / len;
    final Offset perp = Offset(-unit.dy, unit.dx);

    const double hingeHalfWidth = 7.0;
    const double endHalfWidth = 2.0;
    final double bodyLen = (len - 14).clamp(len * 0.3, len);
    final Offset bodyEnd = from + unit * bodyLen;

    final Path legPath = Path()
      ..moveTo(
        from.dx + perp.dx * hingeHalfWidth,
        from.dy + perp.dy * hingeHalfWidth,
      )
      ..lineTo(
        bodyEnd.dx + perp.dx * endHalfWidth,
        bodyEnd.dy + perp.dy * endHalfWidth,
      )
      ..lineTo(
        bodyEnd.dx - perp.dx * endHalfWidth,
        bodyEnd.dy - perp.dy * endHalfWidth,
      )
      ..lineTo(
        from.dx - perp.dx * hingeHalfWidth,
        from.dy - perp.dy * hingeHalfWidth,
      )
      ..close();

    final Paint fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: isNeedleLeg
            ? const [Color(0xFF94A3B8), Color(0xFFF1F5F9), Color(0xFF64748B)]
            : const [Color(0xFF475569), Color(0xFF94A3B8), Color(0xFF1E293B)],
      ).createShader(Rect.fromPoints(from, to).inflate(hingeHalfWidth));
    canvas.drawPath(legPath, fillPaint);
    canvas.drawPath(
      legPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = Colors.black.withOpacity(0.35),
    );
  }

  /// Sharp steel needle at the pivot leg's end, tapering to a point exactly
  /// on the anchor position (where a real compass needle pricks the paper).
  void _drawNeedleTip(Canvas canvas, Offset pivot, Offset hinge) {
    final Offset dir = pivot - hinge;
    final double len = dir.distance;
    if (len < 1) return;
    final Offset unit = dir / len;
    final Offset perp = Offset(-unit.dy, unit.dx);
    final Offset base = pivot - unit * 13;
    const double baseHalfWidth = 2.0;

    final Path needle = Path()
      ..moveTo(
        base.dx + perp.dx * baseHalfWidth,
        base.dy + perp.dy * baseHalfWidth,
      )
      ..lineTo(pivot.dx, pivot.dy)
      ..lineTo(
        base.dx - perp.dx * baseHalfWidth,
        base.dy - perp.dy * baseHalfWidth,
      )
      ..close();
    canvas.drawPath(needle, Paint()..color = const Color(0xFF1E293B));
    canvas.drawCircle(pivot, 1.8, Paint()..color = const Color(0xFF0F172A));
  }

  /// Pencil clamp + wooden pencil + graphite point at the pencil leg's end,
  /// touching the tip exactly at the drawing point.
  void _drawPencilTip(Canvas canvas, Offset tip, Offset hinge) {
    final Offset dir = tip - hinge;
    final double len = dir.distance;
    if (len < 1) return;
    final Offset unit = dir / len;
    final Offset perp = Offset(-unit.dy, unit.dx);

    final Offset clampStart = tip - unit * 23;
    final Offset clampEnd = tip - unit * 15;
    final Offset woodEnd = tip - unit * 5;

    void band(Offset a, Offset b, double halfWidth, Color color) {
      final path = Path()
        ..moveTo(a.dx + perp.dx * halfWidth, a.dy + perp.dy * halfWidth)
        ..lineTo(b.dx + perp.dx * halfWidth, b.dy + perp.dy * halfWidth)
        ..lineTo(b.dx - perp.dx * halfWidth, b.dy - perp.dy * halfWidth)
        ..lineTo(a.dx - perp.dx * halfWidth, a.dy - perp.dy * halfWidth)
        ..close();
      canvas.drawPath(path, Paint()..color = color);
    }

    band(clampStart, clampEnd, 3.2, const Color(0xFF9CA3AF));
    band(clampEnd, woodEnd, 2.6, const Color(0xFFF5C453));

    final Path graphite = Path()
      ..moveTo(woodEnd.dx + perp.dx * 2.6, woodEnd.dy + perp.dy * 2.6)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(woodEnd.dx - perp.dx * 2.6, woodEnd.dy - perp.dy * 2.6)
      ..close();
    canvas.drawPath(graphite, Paint()..color = const Color(0xFF44403C));
  }

  /// Knurled thumbscrew joint where the two legs meet.
  void _drawHinge(Canvas canvas) {
    canvas.drawCircle(
      hinge,
      9,
      Paint()
        ..shader = RadialGradient(
          colors: const [Color(0xFFF1F5F9), Color(0xFF64748B)],
        ).createShader(Rect.fromCircle(center: hinge, radius: 9)),
    );
    canvas.drawCircle(
      hinge,
      9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.black.withOpacity(0.35),
    );
    for (int i = 0; i < 8; i++) {
      final double a = i * pi / 4;
      final Offset p1 = hinge + Offset(cos(a), sin(a)) * 6;
      final Offset p2 = hinge + Offset(cos(a), sin(a)) * 9;
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..color = Colors.black.withOpacity(0.25)
          ..strokeWidth = 1,
      );
    }
    canvas.drawCircle(hinge, 3, Paint()..color = const Color(0xFF334155));
  }

  @override
  bool shouldRepaint(covariant _CompassPainter oldDelegate) => true;
}
