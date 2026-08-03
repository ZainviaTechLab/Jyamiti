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
            left: state.pivot.dx - 15,
            top: state.pivot.dy - 15,
            child: const _CompassDot(color: Color(0xFF6366F1), size: 30),
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
        IgnorePointer(
          child: Positioned(
            left: tip.dx - 14,
            top: tip.dy - 14,
            child: const _CompassDot(color: Color(0xFF1E293B), size: 26),
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

class _CompassDot extends StatelessWidget {
  final Color color;
  final double size;
  const _CompassDot({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
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
    final tip = state.tipWorldPosition;

    // Leg 1: pivot (the sharp point) up to the hinge -- indigo, thicker.
    final pivotLegPaint = Paint()
      ..color = const Color(0xFF6366F1)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(state.pivot, hinge, pivotLegPaint);

    // Leg 2: hinge down to the pencil tip -- dark navy, slightly thinner.
    final pencilLegPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(hinge, tip, pencilLegPaint);

    // Hinge screw/joint.
    final hingePaint = Paint()..color = const Color(0xFF9CA3AF);
    canvas.drawCircle(hinge, 6, hingePaint);
    canvas.drawCircle(
      hinge,
      6,
      Paint()
        ..color = const Color(0xFF6B7280)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

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

  @override
  bool shouldRepaint(covariant _CompassPainter oldDelegate) => true;
}
