import 'dart:math' as math;
import 'package:flutter/material.dart';

class JyamitiLoader extends StatefulWidget {
  final double size;
  final Color? color;
  final double strokeWidth;
  final double? value;
  final Color? backgroundColor;
  final Animation<Color?>? valueColor;
  final StrokeCap strokeCap;

  const JyamitiLoader({
    super.key,
    this.size = 40.0,
    this.color,
    this.strokeWidth = 3.0,
    this.value,
    this.backgroundColor,
    this.valueColor,
    this.strokeCap = StrokeCap.round,
  });

  @override
  State<JyamitiLoader> createState() => _JyamitiLoaderState();
}

class _JyamitiLoaderState extends State<JyamitiLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    if (widget.value == null) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(JyamitiLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == null && !_controller.isAnimating) {
      _controller.repeat();
    } else if (widget.value != null && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resolvedColor =
        widget.valueColor?.value ??
        widget.color ??
        Theme.of(context).primaryColor;
    final resolvedBg =
        widget.backgroundColor ?? resolvedColor.withValues(alpha: 0.1);

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _JyamitiLoaderPainter(
              progress: widget.value ?? _controller.value,
              isDeterminate: widget.value != null,
              color: resolvedColor,
              backgroundColor: resolvedBg,
              strokeWidth: widget.strokeWidth,
              strokeCap: widget.strokeCap,
            ),
          );
        },
      ),
    );
  }
}

class _JyamitiLoaderPainter extends CustomPainter {
  final double progress;
  final bool isDeterminate;
  final Color color;
  final Color backgroundColor;
  final double strokeWidth;
  final StrokeCap strokeCap;

  _JyamitiLoaderPainter({
    required this.progress,
    required this.isDeterminate,
    required this.color,
    required this.backgroundColor,
    required this.strokeWidth,
    required this.strokeCap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = size.width / 2;
    final Offset center = Offset(radius, radius);
    final Rect rect = Rect.fromCircle(
      center: center,
      radius: radius - strokeWidth / 2,
    );

    // 1. Outer Background Track Ring
    final Paint trackPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius - strokeWidth / 2, trackPaint);

    final Paint arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = strokeCap
      ..strokeWidth = strokeWidth;

    if (isDeterminate) {
      // DETERMINATE MODE
      final double clampedProgress = progress.clamp(0.0, 1.0);

      // Arc sweeps proportional to progress
      canvas.drawArc(
        rect,
        -math.pi / 2,
        clampedProgress * 2 * math.pi,
        false,
        arcPaint,
      );

      // Morph interior polygon side count from 3 (Triangle) up to 8 (Octagon) based on progress
      final int sides = 3 + (clampedProgress * 5).floor();
      final double innerRadius = radius * 0.45 * clampedProgress;

      if (innerRadius > 1.0) {
        _drawRegularPolygon(
          canvas,
          center,
          innerRadius,
          sides,
          -math.pi / 2,
          color,
        );
      }
    } else {
      // INDETERMINATE MODE (Advanced Math Animations)

      // Oscillating arc length calculated using a Sine wave: length varies between 60 degrees and 270 degrees
      final double arcSweep =
          (math.pi / 3) +
          ((math.sin(progress * 2 * math.pi) + 1) / 2) * (math.pi * 7 / 6);

      // Rotational movement with smooth parabolic acceleration (Turing harmonic ratio)
      final double rotationAngle =
          -math.pi / 2 +
          (progress * 2 * math.pi) +
          (math.sin(progress * 4 * math.pi) * 0.2);

      canvas.drawArc(rect, rotationAngle, arcSweep, false, arcPaint);

      // Interpolate polygon sides between 3 (Triangle) and 6 (Hexagon) across animation duration
      final double sideValue =
          3 + 3 * ((math.sin(progress * 2 * math.pi) + 1) / 2);
      final int sides = sideValue.round();

      // Pulsating inner geometry radius based on a cosine wave
      final double pulseFactor = 0.45 + 0.1 * math.cos(progress * 4 * math.pi);
      final double innerRadius = radius * pulseFactor;

      // Counter-rotation angle with harmonic frequency scaling (1.5x speed)
      final double innerRotation = -progress * 3 * math.pi;

      // Draw primary geometric morphing shape
      _drawRegularPolygon(
        canvas,
        center,
        innerRadius,
        sides,
        innerRotation,
        color.withValues(alpha: 0.8),
      );

      // Secondary nested geometry: Inner concentric star/ring vertices
      _drawVertexNodes(
        canvas,
        center,
        innerRadius,
        sides,
        innerRotation,
        color,
      );
    }
  }

  /// Draws a regular N-sided polygon using trigonometric radial projection:
  /// x = x_0 + r * cos(theta), y = y_0 + r * sin(theta)
  void _drawRegularPolygon(
    Canvas canvas,
    Offset center,
    double radius,
    int sides,
    double rotation,
    Color strokeColor,
  ) {
    final Paint polyPaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 0.75
      ..strokeCap = strokeCap;

    final Path path = Path();
    final double angleStep = (2 * math.pi) / sides;

    for (int i = 0; i < sides; i++) {
      final double theta = rotation + (i * angleStep);
      final double x = center.dx + radius * math.cos(theta);
      final double y = center.dy + radius * math.sin(theta);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, polyPaint);
  }

  /// Draws mathematical node points at each polygon vertex to emphasize geometry
  void _drawVertexNodes(
    Canvas canvas,
    Offset center,
    double radius,
    int sides,
    double rotation,
    Color nodeColor,
  ) {
    final Paint nodePaint = Paint()
      ..color = nodeColor
      ..style = PaintingStyle.fill;

    final double angleStep = (2 * math.pi) / sides;
    final double nodeRadius = strokeWidth * 0.6;

    for (int i = 0; i < sides; i++) {
      final double theta = rotation + (i * angleStep);
      final double x = center.dx + radius * math.cos(theta);
      final double y = center.dy + radius * math.sin(theta);

      canvas.drawCircle(Offset(x, y), nodeRadius, nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _JyamitiLoaderPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isDeterminate != isDeterminate ||
        oldDelegate.color != color ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.strokeCap != strokeCap;
  }
}
