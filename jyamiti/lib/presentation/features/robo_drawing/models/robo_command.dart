import 'dart:math';
import 'package:flutter/material.dart';
import 'package:math_expressions/math_expressions.dart';
import 'robo_context.dart';
import 'robo_transformations.dart';

void paintRealisticPencil(
  Canvas canvas,
  Offset tipPos, [
  double angle = -pi / 4,
]) {
  canvas.save();
  canvas.translate(tipPos.dx, tipPos.dy);
  canvas.rotate(angle);

  // Graphite tip
  final tipPath = Path()
    ..moveTo(0, 0)
    ..lineTo(8, -3)
    ..lineTo(8, 3)
    ..close();
  canvas.drawPath(tipPath, Paint()..color = const Color(0xFF2C3E50));

  // Wood cone
  final woodPath = Path()
    ..moveTo(8, -3)
    ..lineTo(25, -6)
    ..lineTo(25, 6)
    ..lineTo(8, 3)
    ..close();
  canvas.drawPath(woodPath, Paint()..color = const Color(0xFFF4D03F));

  canvas.drawLine(
    const Offset(8, 0),
    const Offset(25, 0),
    Paint()
      ..color = const Color(0xFFD4AC0D)
      ..strokeWidth = 1,
  );
  canvas.drawLine(
    const Offset(12, -2),
    const Offset(25, -3),
    Paint()
      ..color = const Color(0xFFD4AC0D)
      ..strokeWidth = 1,
  );
  canvas.drawLine(
    const Offset(12, 2),
    const Offset(25, 3),
    Paint()
      ..color = const Color(0xFFD4AC0D)
      ..strokeWidth = 1,
  );

  // Barrel
  final barrelRect = Rect.fromLTWH(25, -6, 50, 12);
  canvas.drawRect(barrelRect, Paint()..color = const Color(0xFFF1C40F));
  canvas.drawLine(
    const Offset(25, -2),
    const Offset(75, -2),
    Paint()
      ..color = const Color(0xFFF39C12)
      ..strokeWidth = 1,
  );
  canvas.drawLine(
    const Offset(25, 2),
    const Offset(75, 2),
    Paint()
      ..color = const Color(0xFFF39C12)
      ..strokeWidth = 1,
  );

  // Jyamiti Brand Logo / Text on the barrel
  final tp = TextPainter(
    text: const TextSpan(
      text: 'Jyamiti',
      style: TextStyle(
        color: Color(0xFFB9770E),
        fontSize: 6,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  canvas.save();
  // Position the text in the middle of the barrel (X=50, Y=0)
  canvas.translate(50, 0);
  // Center the text
  tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
  canvas.restore();

  // Ferrule
  final ferruleRect = Rect.fromLTWH(75, -6, 12, 12);
  canvas.drawRect(ferruleRect, Paint()..color = const Color(0xFFBDC3C7));
  canvas.drawLine(
    const Offset(78, -6),
    const Offset(78, 6),
    Paint()
      ..color = const Color(0xFF95A5A6)
      ..strokeWidth = 1,
  );
  canvas.drawLine(
    const Offset(81, -6),
    const Offset(81, 6),
    Paint()
      ..color = const Color(0xFF95A5A6)
      ..strokeWidth = 1,
  );
  canvas.drawLine(
    const Offset(84, -6),
    const Offset(84, 6),
    Paint()
      ..color = const Color(0xFF95A5A6)
      ..strokeWidth = 1,
  );

  // Eraser
  final eraserRect = RRect.fromLTRBR(87, -6, 95, 6, const Radius.circular(3));
  canvas.drawRRect(eraserRect, Paint()..color = const Color(0xFFF1948A));

  canvas.restore();
}

void paintRealisticProtractor(
  Canvas canvas,
  Offset center,
  double baseAngle,
  double targetAngle,
  double measuredAngle,
  double progress, {
  double opacity = 1.0,
  double translateY = 0.0,
  double extraRotation = 0.0,
  bool drawArc = true,
}) {
  if (opacity <= 0.0) return;
  canvas.save();
  canvas.translate(center.dx, center.dy + translateY);

  double vBase = -baseAngle;
  double vTarget = -targetAngle;
  double vDiff = vTarget - vBase;

  while (vDiff <= -pi) vDiff += 2 * pi;
  while (vDiff > pi) vDiff -= 2 * pi;

  double sweepDirection = (vDiff < 0) ? -1.0 : 1.0;

  canvas.rotate(vBase + extraRotation);

  double radius = 120;

  Path bodyPath = Path()
    ..moveTo(-radius - 20, 0)
    ..lineTo(radius + 20, 0)
    ..arcTo(
      Rect.fromCircle(center: Offset.zero, radius: radius + 20),
      0,
      sweepDirection * pi,
      false,
    )
    ..close();

  Paint plasticPaint = Paint()
    ..color = Colors.lightBlueAccent.withValues(alpha: 0.3 * opacity)
    ..style = PaintingStyle.fill;

  canvas.drawPath(bodyPath, plasticPaint);

  canvas.drawPath(
    bodyPath,
    Paint()
      ..color = Colors.blueGrey.withValues(alpha: 0.8 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2,
  );

  canvas.drawCircle(
    Offset.zero,
    5,
    Paint()
      ..color = Colors.blueGrey.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1,
  );
  canvas.drawLine(
    const Offset(-15, 0),
    const Offset(15, 0),
    Paint()
      ..color = Colors.blueGrey.withValues(alpha: opacity)
      ..strokeWidth = 1,
  );
  canvas.drawLine(
    const Offset(0, 0),
    Offset(0, sweepDirection * 15),
    Paint()
      ..color = Colors.blueGrey.withValues(alpha: opacity)
      ..strokeWidth = 1,
  );

  Paint tickPaint = Paint()
    ..color = Colors.black87.withValues(alpha: opacity)
    ..strokeWidth = 1;
  Paint boldTickPaint = Paint()
    ..color = Colors.black87.withValues(alpha: opacity)
    ..strokeWidth = 2;

  for (int i = 0; i <= 180; i += 5) {
    double rad = sweepDirection * i * pi / 180;
    double innerR = (i % 10 == 0)
        ? radius - 15
        : ((i % 5 == 0) ? radius - 10 : radius - 5);
    Paint p = (i % 10 == 0) ? boldTickPaint : tickPaint;

    Offset p1 = Offset(innerR * cos(rad), innerR * sin(rad));
    Offset p2 = Offset(radius * cos(rad), radius * sin(rad));
    canvas.drawLine(p1, p2, p);

    if (i % 10 == 0) {
      int outerValue = i;
      int innerValue = 180 - i;

      TextPainter tpOuter = TextPainter(
        text: TextSpan(
          text: outerValue.toString(),
          style: TextStyle(
            color: Colors.black.withValues(alpha: opacity),
            fontSize: 9,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      TextPainter tpInner = TextPainter(
        text: TextSpan(
          text: innerValue.toString(),
          style: TextStyle(
            color: Colors.black.withValues(alpha: opacity),
            fontSize: 9,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      double textRot = rad + sweepDirection * pi / 2;
      if (i > 90) textRot += pi;

      // Outer
      canvas.save();
      Offset textPosOuter = Offset(
        (radius - 20) * cos(rad),
        (radius - 20) * sin(rad),
      );
      canvas.translate(textPosOuter.dx, textPosOuter.dy);
      canvas.rotate(textRot);
      tpOuter.paint(canvas, Offset(-tpOuter.width / 2, -tpOuter.height / 2));
      canvas.restore();

      // Inner
      canvas.save();
      Offset textPosInner = Offset(
        (radius - 32) * cos(rad),
        (radius - 32) * sin(rad),
      );
      canvas.translate(textPosInner.dx, textPosInner.dy);
      canvas.rotate(textRot);
      tpInner.paint(canvas, Offset(-tpInner.width / 2, -tpInner.height / 2));
      canvas.restore();
    }
  }

  double currentSweep = vDiff.abs() * progress;

  if (drawArc) {
    Paint arcPaint = Paint()
      ..color = Colors.redAccent.withValues(alpha: 0.6 * opacity)
      ..style = PaintingStyle.fill;
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: 40),
      0,
      sweepDirection * currentSweep,
      true,
      arcPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: 40),
      0,
      sweepDirection * currentSweep,
      true,
      Paint()
        ..color = Colors.red.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  Offset currentPos = Offset(
    radius * cos(sweepDirection * currentSweep),
    radius * sin(sweepDirection * currentSweep),
  );
  canvas.drawLine(
    Offset.zero,
    currentPos,
    Paint()
      ..color = Colors.redAccent.withValues(alpha: opacity)
      ..strokeWidth = 2,
  );

  if (drawArc) {
    double currentDeg = measuredAngle * progress;
    TextPainter measureTp = TextPainter(
      text: TextSpan(
        text: "${currentDeg.toStringAsFixed(1)}°",
        style: TextStyle(
          color: Colors.white.withValues(alpha: opacity),
          fontSize: 14,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              color: Colors.black54.withValues(alpha: opacity),
              blurRadius: 2,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    Offset labelPos = Offset(
      60 * cos(sweepDirection * currentSweep / 2),
      60 * sin(sweepDirection * currentSweep / 2),
    );
    measureTp.paint(
      canvas,
      Offset(
        labelPos.dx - measureTp.width / 2,
        labelPos.dy - measureTp.height / 2,
      ),
    );
  }

  canvas.restore();
}

void paintRealisticCompass(Canvas canvas, Offset center, Offset pencilTip) {
  double d = (pencilTip - center).distance;
  if (d == 0) d = 0.1;

  double L = 160.0;
  if (d / 2 > L - 20) {
    L = d / 2 + 20;
  }

  double h3d = sqrt(L * L - (d / 2) * (d / 2));
  
  Offset m = Offset((center.dx + pencilTip.dx) / 2, (center.dy + pencilTip.dy) / 2);
  
  // 3D projection: the hinge is 'h3d' above the paper in Z.
  // In our 2D canvas, we map +Z to -Y to create an isometric-like view.
  Offset hinge = Offset(m.dx, m.dy - h3d);

  Paint metalPaint = Paint()
    ..color = Colors.blueGrey.shade300
    ..style = PaintingStyle.fill;
  Paint darkMetal = Paint()
    ..color = Colors.blueGrey.shade700
    ..style = PaintingStyle.fill;
  Paint outlinePaint = Paint()
    ..color = Colors.blueGrey.shade800
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;

  void drawNeedleArm() {
    canvas.save();
    canvas.translate(hinge.dx, hinge.dy);
    double angleNeedle = atan2(center.dy - hinge.dy, center.dx - hinge.dx);
    canvas.rotate(angleNeedle);
    
    double dNeedle = (center - hinge).distance;
    
    Path needleArm = Path()
      ..moveTo(0, -5)
      ..lineTo(dNeedle - 20, -3)
      ..lineTo(dNeedle - 20, 3)
      ..lineTo(0, 5)
      ..close();
    canvas.drawPath(needleArm, metalPaint);
    canvas.drawPath(needleArm, outlinePaint);
    
    Path needleTip = Path()
      ..moveTo(dNeedle - 20, -1)
      ..lineTo(dNeedle, 0)
      ..lineTo(dNeedle - 20, 1)
      ..close();
    canvas.drawPath(needleTip, darkMetal);
    
    canvas.restore();
  }

  void drawPencilArm() {
    canvas.save();
    canvas.translate(hinge.dx, hinge.dy);
    double anglePencil = atan2(pencilTip.dy - hinge.dy, pencilTip.dx - hinge.dx);
    canvas.rotate(anglePencil);
    
    double dPencil = (pencilTip - hinge).distance;
    
    Path pencilArm = Path()
      ..moveTo(0, -5)
      ..lineTo(dPencil - 30, -4)
      ..lineTo(dPencil - 30, 4)
      ..lineTo(0, 5)
      ..close();
    canvas.drawPath(pencilArm, metalPaint);
    canvas.drawPath(pencilArm, outlinePaint);
    
    canvas.drawRect(Rect.fromLTWH(dPencil - 35, -7, 20, 14), darkMetal);
    
    Path lead = Path()
      ..moveTo(dPencil - 15, -2)
      ..lineTo(dPencil, 0)
      ..lineTo(dPencil - 15, 2)
      ..close();
    canvas.drawPath(lead, Paint()..color = Colors.black87..style = PaintingStyle.fill);
    
    canvas.drawCircle(Offset(dPencil - 25, 0), 3, metalPaint);
    canvas.drawLine(Offset(dPencil - 27, -1), Offset(dPencil - 23, 1), Paint()..color = Colors.black..strokeWidth = 1);
  
    canvas.restore();
  }

  // Draw arms based on Z-index (Y-coordinate in isometric view)
  // Larger Y means closer to the viewer
  if (pencilTip.dy >= center.dy) {
    drawNeedleArm();
    drawPencilArm();
  } else {
    drawPencilArm();
    drawNeedleArm();
  }

  // 3. Draw Handle (Knob)
  canvas.save();
  canvas.translate(hinge.dx, hinge.dy);
  // Handle points perfectly "UP" in Z, which maps to -Y in 2D.
  canvas.rotate(-pi / 2);
  
  canvas.drawRect(Rect.fromLTWH(0, -4, 20, 8), metalPaint);
  canvas.drawRect(Rect.fromLTWH(0, -4, 20, 8), outlinePaint);
  
  canvas.drawRect(Rect.fromLTWH(20, -6, 15, 12), darkMetal);
  for (int i = 22; i < 34; i+=3) {
      canvas.drawLine(Offset(i.toDouble(), -6), Offset(i.toDouble(), 6), Paint()..color = Colors.black45..strokeWidth = 1);
  }
  canvas.restore();

  // 4. Draw Hinge joint
  canvas.drawCircle(hinge, 7, darkMetal);
  canvas.drawCircle(hinge, 3, metalPaint);
}

/// Base class for all executable drawing commands.
abstract class RoboCommand {
  /// The raw string typed by the user (e.g., 'a=line(A,B)')
  final String rawCommand;

  /// The variable name assigned to this command, if any.
  final String? assignedVar;

  RoboCommand(this.rawCommand, this.assignedVar);

  /// Evaluates the command to compute its spatial coordinates and updates [ctx].
  void evaluate(RoboContext ctx);

  /// Renders the fully completed command statically.
  void paintStatic(Canvas canvas, Size size, RoboContext ctx);

  /// Renders the command dynamically as it is being drawn (progress 0.0 to 1.0).
  /// Also responsible for rendering virtual instruments (like a ruler/pencil).
  void paintAnimated(
    Canvas canvas,
    Size size,
    RoboContext ctx,
    double progress,
  );
}

class RoboPointCommand extends RoboCommand {
  final dynamic xRef; // can be double or a string var reference
  final dynamic yRef;

  RoboPointCommand(String rawCommand, String? assignedVar, this.xRef, this.yRef)
    : super(rawCommand, assignedVar);

  @override
  void evaluate(RoboContext ctx) {
    dynamic xEval = xRef is double ? xRef : ctx.evaluateExpression(xRef);

    if (xEval is Offset && yRef == null) {
      if (assignedVar != null) {
        ctx.setVar(assignedVar!, xEval);
      }
      return;
    }

    double x = (xEval as num?)?.toDouble() ?? 0.0;
    double y = yRef is double
        ? yRef
        : ((ctx.evaluateExpression(yRef) as num?)?.toDouble() ?? 0.0);

    if (assignedVar != null) {
      ctx.setVar(assignedVar!, Offset(x, y));
    }
  }

  @override
  void paintStatic(Canvas canvas, Size size, RoboContext ctx) {
    if (assignedVar == null) return;
    RoboObject? obj = ctx.getObject(assignedVar!);
    if (obj == null || obj.isHidden) return;
    Offset pt = obj.data;

    Offset px = ctx.gridToPixel(pt.dx, pt.dy);

    final paint = Paint()
      ..color = Colors.blue.withValues(alpha: obj.opacity)
      ..style = ctx.currentPointType == 'cross'
          ? PaintingStyle.stroke
          : PaintingStyle.fill
      ..strokeWidth = obj.strokeWidth;

    if (ctx.currentPointType == 'cross') {
      canvas.drawLine(px - const Offset(5, 5), px + const Offset(5, 5), paint);
      canvas.drawLine(
        px - const Offset(5, -5),
        px + const Offset(5, -5),
        paint,
      );
    } else {
      canvas.drawCircle(px, obj.strokeWidth * 2, paint);
    }

    // Draw label
    TextSpan span = TextSpan(
      style: TextStyle(
        color: Colors.blue.withValues(alpha: obj.opacity),
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
      text: assignedVar,
    );
    TextPainter tp = TextPainter(
      text: span,
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, px + const Offset(5, 5));
  }

  @override
  void paintAnimated(
    Canvas canvas,
    Size size,
    RoboContext ctx,
    double progress,
  ) {
    if (assignedVar == null) return;
    RoboObject? obj = ctx.getObject(assignedVar!);
    if (obj == null || obj.isHidden) return;
    Offset pt = obj.data;

    Offset px = ctx.gridToPixel(pt.dx, pt.dy);

    // Animate opacity of the point
    final paint = Paint()
      ..color = Colors.blue.withValues(alpha: obj.opacity * progress)
      ..style = ctx.currentPointType == 'cross'
          ? PaintingStyle.stroke
          : PaintingStyle.fill
      ..strokeWidth = obj.strokeWidth;

    if (ctx.currentPointType == 'cross') {
      canvas.drawLine(
        px - Offset(5 * progress, 5 * progress),
        px + Offset(5 * progress, 5 * progress),
        paint,
      );
      canvas.drawLine(
        px - Offset(5 * progress, -5 * progress),
        px + Offset(5 * progress, -5 * progress),
        paint,
      );
    } else {
      canvas.drawCircle(px, obj.strokeWidth * 2 * progress, paint);
    }

    paintRealisticPencil(canvas, px);
  }
}

class RoboLineCommand extends RoboCommand {
  final dynamic pt1Var;
  final dynamic pt2Var;

  RoboLineCommand(
    String rawCommand,
    String? assignedVar,
    this.pt1Var,
    this.pt2Var,
  ) : super(rawCommand, assignedVar);

  @override
  void evaluate(RoboContext ctx) {
    // We don't necessarily need to store the line itself as a variable unless
    // doing intersections later, but we can store it as a tuple or segment.
    if (assignedVar != null) {
      ctx.setVar(assignedVar!, {'type': 'line', 'p1': pt1Var, 'p2': pt2Var});
    }
  }

  @override
  void paintStatic(Canvas canvas, Size size, RoboContext ctx) {
    RoboObject? obj = assignedVar != null ? ctx.getObject(assignedVar!) : null;
    if (obj != null && obj.isHidden) return;

    Offset? p1 = ctx.evaluateExpression(pt1Var);
    Offset? p2 = ctx.evaluateExpression(pt2Var);
    if (p1 == null || p2 == null) return;

    Offset px1 = ctx.gridToPixel(p1.dx, p1.dy);
    Offset px2 = ctx.gridToPixel(p2.dx, p2.dy);

    final paint = Paint()
      ..color = Colors.purple.withValues(alpha: obj?.opacity ?? 1.0)
      ..strokeWidth = obj?.strokeWidth ?? 2.0
      ..style = PaintingStyle.stroke;

    canvas.drawLine(px1, px2, paint);
  }

  @override
  void paintAnimated(
    Canvas canvas,
    Size size,
    RoboContext ctx,
    double progress,
  ) {
    RoboObject? obj = assignedVar != null ? ctx.getObject(assignedVar!) : null;
    if (obj != null && obj.isHidden) return;

    Offset? p1 = ctx.evaluateExpression(pt1Var);
    Offset? p2 = ctx.evaluateExpression(pt2Var);
    if (p1 == null || p2 == null) return;

    Offset px1 = ctx.gridToPixel(p1.dx, p1.dy);
    Offset px2 = ctx.gridToPixel(p2.dx, p2.dy);

    // Current animated point
    Offset currentPx = Offset.lerp(px1, px2, progress)!;

    // Draw the line up to the current progress
    final linePaint = Paint()
      ..color = Colors.purple.withValues(alpha: obj?.opacity ?? 1.0)
      ..strokeWidth = obj?.strokeWidth ?? 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(px1, currentPx, linePaint);

    // Draw a virtual ruler
    _drawRuler(canvas, px1, px2);

    paintRealisticPencil(canvas, currentPx);
  }

  void _drawRuler(Canvas canvas, Offset p1, Offset p2) {
    final delta = p2 - p1;
    final angle = atan2(delta.dy, delta.dx);
    final length = delta.distance;

    canvas.save();
    canvas.translate(p1.dx, p1.dy);
    canvas.rotate(angle);

    // Ruler rect
    final rect = Rect.fromLTWH(-10, 0, length + 20, 30);
    canvas.drawRect(
      rect,
      Paint()..color = Colors.blueGrey.withValues(alpha: 0.6),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.blueGrey
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Ruler ticks
    final tickPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1;
    for (double x = 0; x <= length; x += 10) {
      canvas.drawLine(Offset(x, 0), Offset(x, x % 50 == 0 ? 10 : 5), tickPaint);
    }

    canvas.restore();
  }
}

class RoboTextCommand extends RoboCommand {
  final String text;
  final dynamic xRef;
  final dynamic yRef;

  RoboTextCommand(String rawCommand, this.text, [this.xRef, this.yRef])
    : super(rawCommand, null);

  @override
  void evaluate(RoboContext ctx) {}

  @override
  void paintStatic(Canvas canvas, Size size, RoboContext ctx) {}

  @override
  void paintAnimated(
    Canvas canvas,
    Size size,
    RoboContext ctx,
    double progress,
  ) {
    bool isTitle = (xRef == null && yRef == null);

    if (!isTitle && progress < 1.0)
      return; // Only show coordinate text when fully loaded

    Offset px;
    if (isTitle) {
      // Draw at the top center of the canvas if no coordinates are provided
      px = Offset(size.width / 2, 40);
    } else {
      double x = 0;
      double y = 0;

      if (xRef != null) {
        x = xRef is double
            ? xRef
            : (ctx.evaluateExpression(xRef) as double? ?? 0.0);
      }
      if (yRef != null) {
        y = yRef is double
            ? yRef
            : (ctx.evaluateExpression(yRef) as double? ?? 0.0);
      }

      px = ctx.gridToPixel(x, y);
    }

    String fullText = text.replaceAll("'", "").replaceAll('"', '');
    String displayText = fullText;

    // Typing animation for title text
    if (isTitle && progress < 1.0) {
      int visibleCount = (fullText.length * progress).round();
      displayText = fullText.substring(0, visibleCount);
    }

    final textPainter = TextPainter(
      text: TextSpan(
        text: displayText,
        style: TextStyle(
          color: isTitle ? Colors.pink : const Color.fromARGB(255, 0, 0, 0),
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    if (displayText.isNotEmpty) {
      Rect textRect = Rect.fromCenter(
        center: px,
        width: textPainter.width + 16,
        height: textPainter.height + 8,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(textRect, const Radius.circular(8)),
        Paint()..color = Colors.white.withValues(alpha: 0.9),
      );
    }

    textPainter.paint(
      canvas,
      Offset(px.dx - textPainter.width / 2, px.dy - textPainter.height / 2),
    );
  }
}

class RoboCircleCommand extends RoboCommand {
  final String centerVar;
  final dynamic radiusRef; // Can be a double or a string reference

  RoboCircleCommand(
    String rawCommand,
    String? assignedVar,
    this.centerVar,
    this.radiusRef,
  ) : super(rawCommand, assignedVar);

  @override
  void evaluate(RoboContext ctx) {
    if (assignedVar != null) {
      ctx.setVar(assignedVar!, {
        'type': 'circle',
        'center': centerVar,
        'radius': radiusRef,
      });
    }
  }

  @override
  void paintStatic(Canvas canvas, Size size, RoboContext ctx) {
    RoboObject? obj = assignedVar != null ? ctx.getObject(assignedVar!) : null;
    if (obj != null && obj.isHidden) return;

    Offset? center = ctx.evaluateExpression(centerVar);
    if (center == null) return;

    double r = radiusRef is double
        ? radiusRef
        : (ctx.evaluateExpression(radiusRef) as double? ?? 0.0);
    if (r <= 0) return;

    Offset pxCenter = ctx.gridToPixel(center.dx, center.dy);
    Offset pxEdge = ctx.gridToPixel(center.dx + r, center.dy);
    double pxRadius = (pxEdge.dx - pxCenter.dx).abs();

    final paint = Paint()
      ..color = Colors.green.withValues(alpha: obj?.opacity ?? 1.0)
      ..strokeWidth = obj?.strokeWidth ?? 2.0
      ..style = (obj?.isFilled ?? false)
          ? PaintingStyle.fill
          : PaintingStyle.stroke;

    canvas.drawCircle(pxCenter, pxRadius, paint);
  }

  @override
  void paintAnimated(
    Canvas canvas,
    Size size,
    RoboContext ctx,
    double progress,
  ) {
    RoboObject? obj = assignedVar != null ? ctx.getObject(assignedVar!) : null;
    if (obj != null && obj.isHidden) return;

    Offset? center = ctx.evaluateExpression(centerVar);
    if (center == null) return;

    double r = radiusRef is double
        ? radiusRef
        : (ctx.evaluateExpression(radiusRef) as double? ?? 0.0);
    if (r <= 0) return;

    Offset pxCenter = ctx.gridToPixel(center.dx, center.dy);
    Offset pxEdge = ctx.gridToPixel(center.dx + r, center.dy);
    double pxRadius = (pxEdge.dx - pxCenter.dx).abs();

    // Draw partial circle
    final paint = Paint()
      ..color = Colors.green.withValues(alpha: obj?.opacity ?? 1.0)
      ..strokeWidth = obj?.strokeWidth ?? 2.0
      ..style = (obj?.isFilled ?? false)
          ? PaintingStyle.fill
          : PaintingStyle.stroke;

    // A circle starts at angle 0 and goes to 2*pi
    double sweepAngle = 2 * pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: pxCenter, radius: pxRadius),
      0,
      sweepAngle,
      (obj?.isFilled ?? false) ? true : false,
      paint,
    );

    // Draw the virtual compass
    // Point of compass is at pxCenter.
    // Pencil of compass is at current angle.
    double currentAngle = sweepAngle;
    Offset pencilOffset = Offset(
      pxCenter.dx + pxRadius * cos(currentAngle),
      pxCenter.dy + pxRadius * sin(currentAngle),
    );

    paintRealisticCompass(canvas, pxCenter, pencilOffset);
  }
}

class RoboArcCommand extends RoboCommand {
  final String centerVar;
  final dynamic radiusRef;
  final dynamic startAngleDegRef;
  final dynamic sweepAngleDegRef;

  RoboArcCommand(
    String rawCommand,
    String? assignedVar,
    this.centerVar,
    this.radiusRef,
    this.startAngleDegRef,
    this.sweepAngleDegRef,
  ) : super(rawCommand, assignedVar);

  @override
  void evaluate(RoboContext ctx) {
    if (assignedVar != null) {
      ctx.setVar(assignedVar!, {
        'type': 'arc',
        'center': centerVar,
        'radius': radiusRef,
      });
    }
  }

  @override
  void paintStatic(Canvas canvas, Size size, RoboContext ctx) {
    RoboObject? obj = assignedVar != null ? ctx.getObject(assignedVar!) : null;
    if (obj != null && obj.isHidden) return;

    Offset? center = ctx.evaluateExpression(centerVar);
    if (center == null) return;

    double r = radiusRef is double
        ? radiusRef
        : (ctx.evaluateExpression(radiusRef) as double? ?? 0.0);
    if (r <= 0) return;

    double startDeg = startAngleDegRef is double
        ? startAngleDegRef
        : (ctx.evaluateExpression(startAngleDegRef) as double? ?? 0.0);
    double sweepDeg = sweepAngleDegRef is double
        ? sweepAngleDegRef
        : (ctx.evaluateExpression(sweepAngleDegRef) as double? ?? 0.0);

    Offset pxCenter = ctx.gridToPixel(center.dx, center.dy);
    Offset pxEdge = ctx.gridToPixel(center.dx + r, center.dy);
    double pxRadius = (pxEdge.dx - pxCenter.dx).abs();

    final paint = Paint()
      ..color = Colors.orange.withValues(alpha: obj?.opacity ?? 1.0)
      ..strokeWidth = obj?.strokeWidth ?? 2.0
      ..style = (obj?.isFilled ?? false)
          ? PaintingStyle.fill
          : PaintingStyle.stroke;

    // Flutter canvas.drawArc uses radians, 0 is right (3 o'clock), positive is clockwise.
    // Our math grid usually has Y going UP, but we already inverted Y in gridToPixel.
    // So angles in standard math (positive = counter-clockwise) need to be negated.
    double startRad = -startDeg * pi / 180.0;
    double sweepRad = -sweepDeg * pi / 180.0;

    canvas.drawArc(
      Rect.fromCircle(center: pxCenter, radius: pxRadius),
      startRad,
      sweepRad,
      (obj?.isFilled ?? false) ? true : false,
      paint,
    );
  }

  @override
  void paintAnimated(
    Canvas canvas,
    Size size,
    RoboContext ctx,
    double progress,
  ) {
    RoboObject? obj = assignedVar != null ? ctx.getObject(assignedVar!) : null;
    if (obj != null && obj.isHidden) return;

    Offset? center = ctx.evaluateExpression(centerVar);
    if (center == null) return;

    double r = radiusRef is double
        ? radiusRef
        : (ctx.evaluateExpression(radiusRef) as double? ?? 0.0);
    if (r <= 0) return;

    double startDeg = startAngleDegRef is double
        ? startAngleDegRef
        : (ctx.evaluateExpression(startAngleDegRef) as double? ?? 0.0);
    double sweepDeg = sweepAngleDegRef is double
        ? sweepAngleDegRef
        : (ctx.evaluateExpression(sweepAngleDegRef) as double? ?? 0.0);

    Offset pxCenter = ctx.gridToPixel(center.dx, center.dy);
    Offset pxEdge = ctx.gridToPixel(center.dx + r, center.dy);
    double pxRadius = (pxEdge.dx - pxCenter.dx).abs();

    final paint = Paint()
      ..color = Colors.orange.withValues(alpha: obj?.opacity ?? 1.0)
      ..strokeWidth = obj?.strokeWidth ?? 2.0
      ..style = (obj?.isFilled ?? false)
          ? PaintingStyle.fill
          : PaintingStyle.stroke;

    double startRad = -startDeg * pi / 180.0;
    double fullSweepRad = -sweepDeg * pi / 180.0;
    double currentSweep = fullSweepRad * progress;

    canvas.drawArc(
      Rect.fromCircle(center: pxCenter, radius: pxRadius),
      startRad,
      currentSweep,
      (obj?.isFilled ?? false) ? true : false,
      paint,
    );

    double currentAngle = startRad + currentSweep;
    Offset pencilOffset = Offset(
      pxCenter.dx + pxRadius * cos(currentAngle),
      pxCenter.dy + pxRadius * sin(currentAngle),
    );

    paintRealisticCompass(canvas, pxCenter, pencilOffset);
  }
}

class RoboStrokeCommand extends RoboCommand {
  final List<String> targetVars;
  final double thickness;

  RoboStrokeCommand(String rawCommand, this.targetVars, this.thickness)
    : super(rawCommand, null);

  @override
  void evaluate(RoboContext ctx) {
    for (String target in targetVars) {
      RoboObject? obj = ctx.getObject(target);
      if (obj != null) {
        obj.strokeWidth = thickness;
      }
    }
  }

  @override
  void paintStatic(Canvas canvas, Size size, RoboContext ctx) {}

  @override
  void paintAnimated(
    Canvas canvas,
    Size size,
    RoboContext ctx,
    double progress,
  ) {}
}

class RoboFadeCommand extends RoboCommand {
  final List<String> targetVars;
  final double fadeFactor;

  RoboFadeCommand(String rawCommand, this.targetVars, this.fadeFactor)
    : super(rawCommand, null);

  @override
  void evaluate(RoboContext ctx) {
    for (String target in targetVars) {
      RoboObject? obj = ctx.getObject(target);
      if (obj != null) {
        obj.opacity = fadeFactor.clamp(0.0, 1.0);
      }
    }
  }

  @override
  void paintStatic(Canvas canvas, Size size, RoboContext ctx) {}

  @override
  void paintAnimated(
    Canvas canvas,
    Size size,
    RoboContext ctx,
    double progress,
  ) {}
}

class RoboVisibilityCommand extends RoboCommand {
  final List<String> targetVars;
  final bool isHidden;

  RoboVisibilityCommand(String rawCommand, this.targetVars, this.isHidden)
    : super(rawCommand, null);

  @override
  void evaluate(RoboContext ctx) {
    for (String target in targetVars) {
      RoboObject? obj = ctx.getObject(target);
      if (obj != null) {
        obj.isHidden = isHidden;
      }
    }
  }

  @override
  void paintStatic(Canvas canvas, Size size, RoboContext ctx) {}

  @override
  void paintAnimated(
    Canvas canvas,
    Size size,
    RoboContext ctx,
    double progress,
  ) {}
}

class RoboPointTypeCommand extends RoboCommand {
  final String pointType;

  RoboPointTypeCommand(String rawCommand, this.pointType)
    : super(rawCommand, null);

  @override
  void evaluate(RoboContext ctx) {
    ctx.currentPointType = pointType;
  }

  @override
  void paintStatic(Canvas canvas, Size size, RoboContext ctx) {}

  @override
  void paintAnimated(
    Canvas canvas,
    Size size,
    RoboContext ctx,
    double progress,
  ) {}
}

class RoboPolygonCommand extends RoboCommand {
  final List<String> pointVars;

  RoboPolygonCommand(String rawCommand, String? assignedVar, this.pointVars)
    : super(rawCommand, assignedVar);

  @override
  void evaluate(RoboContext ctx) {
    if (assignedVar != null) {
      ctx.setVar(assignedVar!, {'type': 'polygon', 'points': pointVars});
    }
  }

  @override
  void paintStatic(Canvas canvas, Size size, RoboContext ctx) {
    _paintPolygon(canvas, size, ctx, 1.0);
  }

  @override
  void paintAnimated(
    Canvas canvas,
    Size size,
    RoboContext ctx,
    double progress,
  ) {
    _paintPolygon(canvas, size, ctx, progress);
  }

  void _paintPolygon(
    Canvas canvas,
    Size size,
    RoboContext ctx,
    double progress,
  ) {
    RoboObject? obj = assignedVar != null ? ctx.getObject(assignedVar!) : null;
    if (obj != null && obj.isHidden) return;

    List<Offset> points = [];
    for (String pVar in pointVars) {
      Offset? p = ctx.evaluateExpression(pVar);
      if (p != null) {
        points.add(ctx.gridToPixel(p.dx, p.dy));
      }
    }
    if (points.length < 3) return;

    final path = Path();
    path.moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    path.close();

    final paint = Paint()
      ..color = Colors.teal.withValues(alpha: (obj?.opacity ?? 1.0) * progress)
      ..strokeWidth = obj?.strokeWidth ?? 2.0
      ..style = (obj?.isFilled ?? false)
          ? PaintingStyle.fill
          : PaintingStyle.stroke;

    canvas.drawPath(path, paint);
  }
}

class RoboDashCommand extends RoboCommand {
  final String pt1Var;
  final String pt2Var;
  final double dashLength;
  final double gapLength;

  RoboDashCommand(
    String rawCommand,
    String? assignedVar,
    this.pt1Var,
    this.pt2Var,
    this.dashLength,
    this.gapLength,
  ) : super(rawCommand, assignedVar);

  @override
  void evaluate(RoboContext ctx) {
    if (assignedVar != null) {
      ctx.setVar(assignedVar!, {'type': 'dash', 'p1': pt1Var, 'p2': pt2Var});
    }
  }

  @override
  void paintStatic(Canvas canvas, Size size, RoboContext ctx) {
    _paintDash(canvas, size, ctx, 1.0);
  }

  @override
  void paintAnimated(
    Canvas canvas,
    Size size,
    RoboContext ctx,
    double progress,
  ) {
    _paintDash(canvas, size, ctx, progress);
  }

  void _paintDash(Canvas canvas, Size size, RoboContext ctx, double progress) {
    RoboObject? obj = assignedVar != null ? ctx.getObject(assignedVar!) : null;
    if (obj != null && obj.isHidden) return;

    Offset? p1 = ctx.evaluateExpression(pt1Var);
    Offset? p2 = ctx.evaluateExpression(pt2Var);
    if (p1 == null || p2 == null) return;

    Offset px1 = ctx.gridToPixel(p1.dx, p1.dy);
    Offset px2 = ctx.gridToPixel(p2.dx, p2.dy);
    Offset currentPx = Offset.lerp(px1, px2, progress)!;

    final paint = Paint()
      ..color = Colors.brown.withValues(alpha: obj?.opacity ?? 1.0)
      ..strokeWidth = obj?.strokeWidth ?? 2.0
      ..style = PaintingStyle.stroke;

    final delta = currentPx - px1;
    final dist = delta.distance;
    if (dist <= 0) return;

    final direction = delta / dist;
    double currentDist = 0;

    double pxDash = dashLength * 20;
    double pxGap = gapLength * 20;

    while (currentDist < dist) {
      double endDist = currentDist + pxDash;
      if (endDist > dist) endDist = dist;

      canvas.drawLine(
        px1 + direction * currentDist,
        px1 + direction * endDist,
        paint,
      );

      currentDist += pxDash + pxGap;
    }
  }
}

class RoboGroupCommand extends RoboCommand {
  final List<String> groupedVars;

  RoboGroupCommand(String rawCommand, String? assignedVar, this.groupedVars)
    : super(rawCommand, assignedVar);

  @override
  void evaluate(RoboContext ctx) {
    if (assignedVar != null) {
      ctx.setVar(assignedVar!, {'type': 'group', 'items': groupedVars});
    }
  }

  @override
  void paintStatic(Canvas canvas, Size size, RoboContext ctx) {}

  @override
  void paintAnimated(
    Canvas canvas,
    Size size,
    RoboContext ctx,
    double progress,
  ) {}
}

class RoboTransformCommand extends RoboCommand {
  final String targetVar;
  final String type; // 'rotate', 'translate', 'dilate', 'reflect', 'reverse'
  final List<dynamic> transformArgs;

  RoboTransformCommand(
    String rawCommand,
    String? assignedVar,
    this.targetVar,
    this.type,
    this.transformArgs,
  ) : super(rawCommand, assignedVar);

  @override
  void evaluate(RoboContext ctx) {
    if (assignedVar == null) return;

    dynamic data = ctx.evaluateExpression(targetVar);
    if (data == null) return;

    dynamic transformedData;

    try {
      if (type == 'rotate') {
        double angleDeg = transformArgs[0] is double
            ? transformArgs[0]
            : (ctx.evaluateExpression(transformArgs[0]) as double? ?? 0.0);
        Offset origin = const Offset(0, 0);
        if (transformArgs.length > 1) {
          Offset? refPt = ctx.evaluateExpression(transformArgs[1]);
          if (refPt != null) origin = refPt;
        }
        transformedData = RoboTransformations.rotate(
          ctx,
          data,
          angleDeg,
          origin,
        );
      } else if (type == 'translate') {
        double tx = transformArgs[0] is double
            ? transformArgs[0]
            : (ctx.evaluateExpression(transformArgs[0]) as double? ?? 0.0);
        double ty = transformArgs[1] is double
            ? transformArgs[1]
            : (ctx.evaluateExpression(transformArgs[1]) as double? ?? 0.0);
        if (transformArgs.length > 2) {
          Offset? refPt = ctx.evaluateExpression(transformArgs[2]);
          if (refPt != null) {
            tx -= refPt.dx;
            ty -= refPt.dy;
          }
        }
        transformedData = RoboTransformations.translate(ctx, data, tx, ty);
      } else if (type == 'dilate') {
        double scale = transformArgs[0] is double
            ? transformArgs[0]
            : (ctx.evaluateExpression(transformArgs[0]) as double? ?? 1.0);
        Offset origin = const Offset(0, 0);
        if (transformArgs.length > 1) {
          Offset? refPt = ctx.evaluateExpression(transformArgs[1]);
          if (refPt != null) origin = refPt;
        }
        transformedData = RoboTransformations.dilate(ctx, data, scale, origin);
      } else if (type == 'reflect') {
        dynamic lineData = ctx.evaluateExpression(transformArgs[0]);
        if (lineData is Map && lineData['type'] == 'line') {
          Offset? p1 = ctx.evaluateExpression(lineData['p1']);
          Offset? p2 = ctx.evaluateExpression(lineData['p2']);
          if (p1 != null && p2 != null) {
            transformedData = RoboTransformations.reflect(ctx, data, p1, p2);
          }
        }
      } else if (type == 'reverse') {
        transformedData = RoboTransformations.applyTransform(
          ctx,
          data,
          (Offset p) => Offset(-p.dx, -p.dy),
          rotateAngleDeg: 180,
        );
      }

      if (transformedData != null) {
        ctx.setVar(assignedVar!, transformedData);
      }
    } catch (e) {
      debugPrint("Transformation Error: \$e");
    }
  }

  @override
  void paintStatic(Canvas canvas, Size size, RoboContext ctx) {
    if (assignedVar == null) return;
    RoboObject? obj = ctx.getObject(assignedVar!);
    if (obj == null || obj.isHidden) return;

    _paintGeneric(canvas, size, ctx, assignedVar!, 1.0);
  }

  @override
  void paintAnimated(
    Canvas canvas,
    Size size,
    RoboContext ctx,
    double progress,
  ) {
    if (assignedVar == null) return;
    RoboObject? obj = ctx.getObject(assignedVar!);
    if (obj == null || obj.isHidden) return;

    _paintGeneric(canvas, size, ctx, assignedVar!, progress);
  }

  Path buildPathForVar(RoboContext ctx, String varName) {
    dynamic data = ctx.evaluateExpression(varName);
    Path path = Path();
    if (data is Map) {
      String type = data['type'];
      if (type == 'polygon' || type == 'path') {
        List<String> pts = List<String>.from(data['points']);
        for (int i = 0; i < pts.length; i++) {
          Offset? p = ctx.evaluateExpression(pts[i]);
          if (p == null) continue;
          Offset px = ctx.gridToPixel(p.dx, p.dy);
          if (i == 0)
            path.moveTo(px.dx, px.dy);
          else
            path.lineTo(px.dx, px.dy);
        }
        if (type == 'polygon') path.close();
      } else if (type == 'circle') {
        Offset? c = ctx.evaluateExpression(data['center']);
        double r = data['radius'] is double
            ? data['radius']
            : (ctx.evaluateExpression(data['radius']) as double? ?? 1.0);
        if (c != null) {
          Offset pxCenter = ctx.gridToPixel(c.dx, c.dy);
          Offset pxEdge = ctx.gridToPixel(c.dx + r, c.dy);
          double pxRadius = (pxEdge.dx - pxCenter.dx).abs();
          path.addOval(Rect.fromCircle(center: pxCenter, radius: pxRadius));
        }
      } else if (type == 'arc') {
        Offset? c = ctx.evaluateExpression(data['center']);
        double r = data['radius'] is double
            ? data['radius']
            : (ctx.evaluateExpression(data['radius']) as double? ?? 1.0);
        double st = data['start'] is double
            ? data['start']
            : (ctx.evaluateExpression(data['start']) as double? ?? 0.0);
        double sw = data['sweep'] is double
            ? data['sweep']
            : (ctx.evaluateExpression(data['sweep']) as double? ?? 360.0);
        if (c != null) {
          Offset pxCenter = ctx.gridToPixel(c.dx, c.dy);
          Offset pxEdge = ctx.gridToPixel(c.dx + r, c.dy);
          double pxRadius = (pxEdge.dx - pxCenter.dx).abs();
          path.addArc(
            Rect.fromCircle(center: pxCenter, radius: pxRadius),
            -st * pi / 180.0,
            -sw * pi / 180.0,
          );
        }
      } else if (type == 'region') {
        Path p1 = buildPathForVar(ctx, data['s1']);
        Path p2 = buildPathForVar(ctx, data['s2']);
        String op = data['operation'];
        PathOperation po = PathOperation.intersect;
        if (op == 'or') po = PathOperation.union;
        if (op == 'diff') po = PathOperation.difference;
        path = Path.combine(po, p1, p2);
      }
    }
    return path;
  }

  void _paintGeneric(
    Canvas canvas,
    Size size,
    RoboContext ctx,
    String varName,
    double progress,
  ) {
    dynamic data = ctx.evaluateExpression(varName);
    if (data == null) return;

    if (data is Offset) {
      RoboPointCommand(
        "",
        varName,
        data.dx,
        data.dy,
      ).paintAnimated(canvas, size, ctx, progress);
    } else if (data is Map) {
      String type = data['type'];
      if (type == 'line') {
        RoboLineCommand(
          "",
          varName,
          data['p1'],
          data['p2'],
        ).paintAnimated(canvas, size, ctx, progress);
      } else if (type == 'circle') {
        RoboCircleCommand(
          "",
          varName,
          data['center'],
          data['radius'],
        ).paintAnimated(canvas, size, ctx, progress);
      } else if (type == 'arc') {
        RoboArcCommand(
          "",
          varName,
          data['center'],
          data['radius'],
          data['start'],
          data['sweep'],
        ).paintAnimated(canvas, size, ctx, progress);
      } else if (type == 'polygon') {
        RoboPolygonCommand(
          "",
          varName,
          List<String>.from(data['points']),
        ).paintAnimated(canvas, size, ctx, progress);
      } else if (type == 'polygon_angles') {
        dynamic poly = ctx.evaluateExpression(data['polygon']);
        if (poly is Map && poly['type'] == 'polygon') {
          List<String> pts = List<String>.from(poly['points']);
          for (int i = 0; i < pts.length; i++) {
            String pPrev = pts[(i - 1 + pts.length) % pts.length];
            String pCurr = pts[i];
            String pNext = pts[(i + 1) % pts.length];

            Offset? ptPrev = ctx.evaluateExpression(pPrev);
            Offset? ptCurr = ctx.evaluateExpression(pCurr);
            Offset? ptNext = ctx.evaluateExpression(pNext);

            if (ptPrev != null && ptCurr != null && ptNext != null) {
              double a1 = atan2(ptPrev.dy - ptCurr.dy, ptPrev.dx - ptCurr.dx);
              double a2 = atan2(ptNext.dy - ptCurr.dy, ptNext.dx - ptCurr.dx);

              double a1Deg = a1 * 180 / pi;
              double a2Deg = a2 * 180 / pi;
              if (a1Deg < 0) a1Deg += 360;
              if (a2Deg < 0) a2Deg += 360;

              double sweep = a2Deg - a1Deg;
              if (sweep < 0) sweep += 360;
              if (sweep > 180)
                sweep = 360 - sweep; // Use the interior/smaller angle

              String label = sweep.toStringAsFixed(1) + "°";

              double midAngle = a1 + (a2 - a1) / 2;
              if (sweep == 360 - (a2Deg - a1Deg)) {
                midAngle += pi;
              }

              Offset pxCurr = ctx.gridToPixel(ptCurr.dx, ptCurr.dy);
              Offset pxMid = ctx.gridToPixel(
                ptCurr.dx + cos(midAngle),
                ptCurr.dy + sin(midAngle),
              );

              Offset dir = pxMid - pxCurr;
              if (dir.distance != 0) dir = dir / dir.distance;
              Offset pxText =
                  pxCurr + dir * 25; // Push text 25 pixels away from vertex

              final textPainter = TextPainter(
                text: TextSpan(
                  text: label,
                  style: TextStyle(
                    color: Colors.black.withValues(alpha: progress),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                textDirection: TextDirection.ltr,
              );
              textPainter.layout();
              textPainter.paint(
                canvas,
                Offset(
                  pxText.dx - textPainter.width / 2,
                  pxText.dy - textPainter.height / 2,
                ),
              );
            }
          }
        }
      } else if (type == 'region') {
        RoboObject? obj = ctx.getObject(varName);
        Path path = buildPathForVar(ctx, varName);
        final paint = Paint()
          ..color = Colors.blue.withValues(
            alpha: (obj?.opacity ?? 0.3) * progress,
          )
          ..strokeWidth = obj?.strokeWidth ?? 2.0
          ..style = (obj?.isFilled ?? false)
              ? PaintingStyle.fill
              : PaintingStyle.stroke;
        canvas.drawPath(path, paint);
      } else if (type == 'group') {
        for (String itemVar in data['items']) {
          _paintGeneric(canvas, size, ctx, itemVar, progress);
        }
      } else if (type == 'path') {
        List<String> points = List<String>.from(data['points']);
        if (points.isEmpty) return;

        RoboObject? obj = ctx.getObject(varName);
        double opacity = obj?.opacity ?? 1.0;
        double strokeWidth = obj?.strokeWidth ?? 2.0;

        final paint = Paint()
          ..color = Colors.blue.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round;

        Path path = Path();
        Offset? firstPoint = ctx.evaluateExpression(points[0]);
        if (firstPoint != null) {
          Offset pxFirst = ctx.gridToPixel(firstPoint.dx, firstPoint.dy);
          path.moveTo(pxFirst.dx, pxFirst.dy);

          int limit = (points.length * progress).ceil();
          for (int i = 1; i < limit; i++) {
            Offset? p = ctx.evaluateExpression(points[i]);
            if (p != null) {
              Offset px = ctx.gridToPixel(p.dx, p.dy);
              path.lineTo(px.dx, px.dy);
            }
          }
          canvas.drawPath(path, paint);
        }
      }
    }
  }
}

class RoboMathCommand extends RoboCommand {
  final String func;
  final List<dynamic> args;

  String? _anonVar;

  RoboMathCommand(String rawCommand, String? assignedVar, this.func, this.args)
    : super(rawCommand, assignedVar);

  String? get _effectiveVar => assignedVar ?? _anonVar;

  @override
  void evaluate(RoboContext ctx) {
    dynamic result;
    try {
      if (func == 'X') {
        Offset? pt = ctx.evaluateExpression(args[0]);
        if (pt != null) result = pt.dx;
      } else if (func == 'Y') {
        Offset? pt = ctx.evaluateExpression(args[0]);
        if (pt != null) result = pt.dy;
      } else if (func == 'dist') {
        if (args.length == 2) {
          Offset? p1 = ctx.evaluateExpression(args[0]);
          Offset? p2 = ctx.evaluateExpression(args[1]);
          if (p1 != null && p2 != null) result = (p1 - p2).distance;
        } else if (args.length == 1) {
          dynamic lineData = ctx.evaluateExpression(args[0]);
          if (lineData is Map && lineData['type'] == 'line') {
            Offset? p1 = ctx.evaluateExpression(lineData['p1']);
            Offset? p2 = ctx.evaluateExpression(lineData['p2']);
            if (p1 != null && p2 != null) result = (p1 - p2).distance;
          }
        }
      } else if (func == 'pos') {
        dynamic shape = ctx.evaluateExpression(args[0]);
        int idx = (ctx.evaluateExpression(args[1]) as double? ?? 1.0).toInt();
        if (shape is Map) {
          if (shape['type'] == 'polygon') {
            List<String> points = shape['points'];
            if (idx >= 1 && idx <= points.length) {
              result = ctx.evaluateExpression(points[idx - 1]);
            }
          } else if (shape['type'] == 'line') {
            if (idx == 1) result = ctx.evaluateExpression(shape['p1']);
            if (idx == 2) result = ctx.evaluateExpression(shape['p2']);
          }
        }
      } else if (func == 'interpolate') {
        Offset? p1 = ctx.evaluateExpression(args[0]);
        Offset? p2 = ctx.evaluateExpression(args[1]);
        double ratio = args[2] is double
            ? args[2]
            : (ctx.evaluateExpression(args[2]) as double? ?? 0.5);
        if (p1 != null && p2 != null) {
          result = Offset.lerp(p1, p2, ratio);
        }
      } else if (func == 'project') {
        Offset? pt = ctx.evaluateExpression(args[0]);
        dynamic lineData = ctx.evaluateExpression(args[1]);
        if (pt != null && lineData is Map && lineData['type'] == 'line') {
          Offset? p1 = ctx.evaluateExpression(lineData['p1']);
          Offset? p2 = ctx.evaluateExpression(lineData['p2']);
          if (p1 != null && p2 != null) {
            double dx = p2.dx - p1.dx;
            double dy = p2.dy - p1.dy;
            double lenSq = dx * dx + dy * dy;
            if (lenSq != 0) {
              double t = ((pt.dx - p1.dx) * dx + (pt.dy - p1.dy) * dy) / lenSq;
              result = Offset(p1.dx + t * dx, p1.dy + t * dy);
            } else {
              result = p1;
            }
          }
        }
      } else if (func == 'findangle') {
        if (args.length == 1) {
          dynamic obj1 = ctx.evaluateExpression(args[0]);
          if (obj1 is Map && obj1['type'] == 'polygon') {
            result = {'type': 'polygon_angles', 'polygon': args[0]};
          }
        } else if (args.length >= 2) {
          dynamic line1Data = ctx.evaluateExpression(args[0]);
          dynamic line2Data = ctx.evaluateExpression(args[1]);
          if (line1Data is Map &&
              line2Data is Map &&
              line1Data['type'] == 'line' &&
              line2Data['type'] == 'line') {
            Offset? p1 = ctx.evaluateExpression(line1Data['p1']);
            Offset? p2 = ctx.evaluateExpression(line1Data['p2']);
            Offset? p3 = ctx.evaluateExpression(line2Data['p1']);
            Offset? p4 = ctx.evaluateExpression(line2Data['p2']);
            if (p1 != null && p2 != null && p3 != null && p4 != null) {
              double angle1 = atan2(p2.dy - p1.dy, p2.dx - p1.dx);
              double angle2 = atan2(p4.dy - p3.dy, p4.dx - p3.dx);
              double diff = ((angle2 - angle1) * 180.0 / pi) % 360.0;
              if (diff < 0) diff += 360.0;
              if (diff > 180.0) diff = 360.0 - diff;

              double denom =
                  (p1.dx - p2.dx) * (p3.dy - p4.dy) -
                  (p1.dy - p2.dy) * (p3.dx - p4.dx);
              Offset vertex;
              if (denom != 0) {
                double px =
                    ((p1.dx * p2.dy - p1.dy * p2.dx) * (p3.dx - p4.dx) -
                        (p1.dx - p2.dx) * (p3.dx * p4.dy - p3.dy * p4.dx)) /
                    denom;
                double py =
                    ((p1.dx * p2.dy - p1.dy * p2.dx) * (p3.dy - p4.dy) -
                        (p1.dy - p2.dy) * (p3.dx * p4.dy - p3.dy * p4.dx)) /
                    denom;
                vertex = Offset(px, py);
              } else {
                vertex = p2;
              }

              result = {
                'type': 'measured_angle',
                'value': diff,
                'vertex': RoboTransformations.generateAnonVar(ctx, vertex),
                'baseAngle': angle1,
                'targetAngle': angle2,
              };
            }
          }
        }
      } else if (func == 'perp' || func == 'parallel') {
        dynamic lineData = ctx.evaluateExpression(args[0]);
        Offset? pt = ctx.evaluateExpression(args[1]);
        double length = args.length > 2
            ? (args[2] is double
                  ? args[2]
                  : (ctx.evaluateExpression(args[2]) as double? ?? 10.0))
            : 10.0;

        if (lineData is Map && lineData['type'] == 'line' && pt != null) {
          Offset? p1 = ctx.evaluateExpression(lineData['p1']);
          Offset? p2 = ctx.evaluateExpression(lineData['p2']);
          if (p1 != null && p2 != null) {
            double dx = p2.dx - p1.dx;
            double dy = p2.dy - p1.dy;
            double len = sqrt(dx * dx + dy * dy);
            if (len != 0) {
              double dirX = dx / len;
              double dirY = dy / len;

              if (func == 'perp') {
                // Perpendicular vector (-dy, dx)
                double px = -dirY;
                double py = dirX;
                // Line centered at pt
                Offset start = Offset(
                  pt.dx - px * (length / 2),
                  pt.dy - py * (length / 2),
                );
                Offset end = Offset(
                  pt.dx + px * (length / 2),
                  pt.dy + py * (length / 2),
                );

                String anonStart = RoboTransformations.generateAnonVar(
                  ctx,
                  start,
                );
                String anonEnd = RoboTransformations.generateAnonVar(ctx, end);
                result = {'type': 'line', 'p1': anonStart, 'p2': anonEnd};
              } else {
                // Parallel vector (dx, dy)
                Offset start = Offset(
                  pt.dx - dirX * (length / 2),
                  pt.dy - dirY * (length / 2),
                );
                Offset end = Offset(
                  pt.dx + dirX * (length / 2),
                  pt.dy + dirY * (length / 2),
                );

                String anonStart = RoboTransformations.generateAnonVar(
                  ctx,
                  start,
                );
                String anonEnd = RoboTransformations.generateAnonVar(ctx, end);
                result = {'type': 'line', 'p1': anonStart, 'p2': anonEnd};
              }
            }
          }
        }
      } else if (func == 'angle') {
        Offset? p1 = ctx.evaluateExpression(args[0]);
        Offset? p2 = ctx.evaluateExpression(args[1]);
        double degrees = args[2] is double
            ? args[2]
            : (ctx.evaluateExpression(args[2]) as double? ?? 0.0);
        double ratio = args.length > 3
            ? (args[3] is double
                  ? args[3]
                  : (ctx.evaluateExpression(args[3]) as double? ?? 0.0))
            : 0.0;

        if (p1 != null && p2 != null) {
          Offset center = Offset.lerp(p1, p2, ratio)!;
          double baseAngle = atan2(p2.dy - p1.dy, p2.dx - p1.dx);
          double radius =
              (p1 - p2).distance * 0.3; // Arbitrary radius for the arc
          if (radius == 0) radius = 2.0;

          double sweep = degrees;
          String anonArc = RoboTransformations.generateAnonVar(ctx, {
            'type': 'arc',
            'center': RoboTransformations.generateAnonVar(ctx, center),
            'radius': radius,
            'start': baseAngle * 180 / pi,
            'sweep': sweep,
          });

          Offset endPt = Offset(
            center.dx + radius * 1.5 * cos(baseAngle + degrees * pi / 180),
            center.dy + radius * 1.5 * sin(baseAngle + degrees * pi / 180),
          );
          String anonLine = RoboTransformations.generateAnonVar(ctx, {
            'type': 'line',
            'p1': RoboTransformations.generateAnonVar(ctx, center),
            'p2': RoboTransformations.generateAnonVar(ctx, endPt),
          });

          result = {
            'type': 'group',
            'items': [anonArc, anonLine],
          };
        }
      } else if (func == 'intersect') {
        dynamic obj1 = ctx.evaluateExpression(args[0]);
        dynamic obj2 = ctx.evaluateExpression(args[1]);
        int idx = args.length > 2
            ? (ctx.evaluateExpression(args[2]) as double? ?? 1.0).toInt()
            : 1;

        if (obj1 is Map && obj2 is Map) {
          // Treat 'arc' as 'circle' for intersections
          String type1 = obj1['type'] == 'arc' ? 'circle' : obj1['type'];
          String type2 = obj2['type'] == 'arc' ? 'circle' : obj2['type'];

          if (type1 == 'line' && type2 == 'line') {
            Offset? p1 = ctx.evaluateExpression(obj1['p1']);
            Offset? p2 = ctx.evaluateExpression(obj1['p2']);
            Offset? p3 = ctx.evaluateExpression(obj2['p1']);
            Offset? p4 = ctx.evaluateExpression(obj2['p2']);
            if (p1 != null && p2 != null && p3 != null && p4 != null) {
              double denom =
                  (p1.dx - p2.dx) * (p3.dy - p4.dy) -
                  (p1.dy - p2.dy) * (p3.dx - p4.dx);
              if (denom != 0) {
                double px =
                    ((p1.dx * p2.dy - p1.dy * p2.dx) * (p3.dx - p4.dx) -
                        (p1.dx - p2.dx) * (p3.dx * p4.dy - p3.dy * p4.dx)) /
                    denom;
                double py =
                    ((p1.dx * p2.dy - p1.dy * p2.dx) * (p3.dy - p4.dy) -
                        (p1.dy - p2.dy) * (p3.dx * p4.dy - p3.dy * p4.dx)) /
                    denom;
                result = Offset(px, py);
              }
            }
          } else if ((type1 == 'line' && type2 == 'circle') ||
              (type1 == 'circle' && type2 == 'line')) {
            Map lineObj = type1 == 'line' ? obj1 : obj2;
            Map circObj = type1 == 'circle' ? obj1 : obj2;
            Offset? p1 = ctx.evaluateExpression(lineObj['p1']);
            Offset? p2 = ctx.evaluateExpression(lineObj['p2']);
            Offset? center = ctx.evaluateExpression(circObj['center']);
            double radius = circObj['radius'] is double
                ? circObj['radius']
                : (ctx.evaluateExpression(circObj['radius']) as double? ?? 1.0);

            if (p1 != null && p2 != null && center != null) {
              // Shift line so circle is at origin
              double x1 = p1.dx - center.dx;
              double y1 = p1.dy - center.dy;
              double x2 = p2.dx - center.dx;
              double y2 = p2.dy - center.dy;

              double dx = x2 - x1;
              double dy = y2 - y1;
              double dr = sqrt(dx * dx + dy * dy);
              double D = x1 * y2 - x2 * y1;

              double discriminant = radius * radius * dr * dr - D * D;
              if (discriminant >= 0) {
                double signDy = dy < 0 ? -1 : 1;
                double ix1 =
                    (D * dy + signDy * dx * sqrt(discriminant)) / (dr * dr);
                double iy1 =
                    (-D * dx + dy.abs() * sqrt(discriminant)) / (dr * dr);
                double ix2 =
                    (D * dy - signDy * dx * sqrt(discriminant)) / (dr * dr);
                double iy2 =
                    (-D * dx - dy.abs() * sqrt(discriminant)) / (dr * dr);

                Offset int1 = Offset(ix1 + center.dx, iy1 + center.dy);
                Offset int2 = Offset(ix2 + center.dx, iy2 + center.dy);

                if (idx == 1)
                  result = int1;
                else
                  result = int2;
              }
            }
          } else if (type1 == 'circle' && type2 == 'circle') {
            Offset? c1 = ctx.evaluateExpression(obj1['center']);
            double r1 = obj1['radius'] is double
                ? obj1['radius']
                : (ctx.evaluateExpression(obj1['radius']) as double? ?? 1.0);
            Offset? c2 = ctx.evaluateExpression(obj2['center']);
            double r2 = obj2['radius'] is double
                ? obj2['radius']
                : (ctx.evaluateExpression(obj2['radius']) as double? ?? 1.0);

            if (c1 != null && c2 != null) {
              double d = (c2 - c1).distance;
              if (d > 0 && d <= r1 + r2 && d >= (r1 - r2).abs()) {
                double a = (r1 * r1 - r2 * r2 + d * d) / (2 * d);
                double h = sqrt(r1 * r1 - a * a);

                double p2x = c1.dx + a * (c2.dx - c1.dx) / d;
                double p2y = c1.dy + a * (c2.dy - c1.dy) / d;

                double ix1 = p2x + h * (c2.dy - c1.dy) / d;
                double iy1 = p2y - h * (c2.dx - c1.dx) / d;
                double ix2 = p2x - h * (c2.dy - c1.dy) / d;
                double iy2 = p2y + h * (c2.dx - c1.dx) / d;

                Offset int1 = Offset(ix1, iy1);
                Offset int2 = Offset(ix2, iy2);

                if (idx == 1)
                  result = int1;
                else
                  result = int2;
              }
            }
          }
        }
      }

      if (result != null) {
        if (assignedVar == null && _anonVar == null) {
          _anonVar = RoboTransformations.generateAnonVar(ctx, result);
        }
        String targetVar = _effectiveVar!;

        ctx.setVar(targetVar, result);
        if (assignedVar == null) {
          ctx.variables[targetVar]?.isHidden = false;
        }

        if (result is Map && result['type'] == 'measured_angle') {
          ctx.variables[targetVar]?.speedOverride = 0.5;
        }
      }
    } catch (e) {
      debugPrint("Math Error: \$e");
    }
  }

  void _paintPencilArc(
    Canvas canvas,
    Offset center,
    double baseAngle,
    double targetAngle,
    double measuredAngle,
    double progress, {
    bool showPencil = true,
  }) {
    if (progress <= 0.0) return;
    double vBase = -baseAngle;
    double vTarget = -targetAngle;
    double vDiff = vTarget - vBase;
    while (vDiff <= -pi) vDiff += 2 * pi;
    while (vDiff > pi) vDiff -= 2 * pi;
    double sweepDirection = (vDiff < 0) ? -1.0 : 1.0;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(vBase);

    double currentSweep = vDiff.abs() * progress;

    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: 40),
      0,
      sweepDirection * currentSweep,
      false,
      Paint()
        ..color = Colors.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    if (showPencil && progress < 1.0) {
      Offset pencilPos = Offset(
        40 * cos(sweepDirection * currentSweep),
        40 * sin(sweepDirection * currentSweep),
      );
      double pencilRot =
          (sweepDirection * currentSweep) + (sweepDirection * pi / 2);
      paintRealisticPencil(canvas, pencilPos, pencilRot - pi / 4);
    }

    double currentDeg = measuredAngle * progress;
    TextPainter measureTp = TextPainter(
      text: TextSpan(
        text: "${currentDeg.toStringAsFixed(1)}°",
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(color: Colors.black54, blurRadius: 2)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    Offset labelPos = Offset(
      60 * cos(sweepDirection * currentSweep / 2),
      60 * sin(sweepDirection * currentSweep / 2),
    );
    measureTp.paint(
      canvas,
      Offset(
        labelPos.dx - measureTp.width / 2,
        labelPos.dy - measureTp.height / 2,
      ),
    );

    canvas.restore();
  }

  @override
  void paintStatic(Canvas canvas, Size size, RoboContext ctx) {
    if (_effectiveVar != null) {
      dynamic data = ctx.getVar(_effectiveVar!);
      if (data is Map && data['type'] == 'measured_angle') {
        Offset? vertex = ctx.evaluateExpression(data['vertex']);
        if (vertex != null) {
          _paintPencilArc(
            canvas,
            ctx.gridToPixel(vertex.dx, vertex.dy),
            data['baseAngle'],
            data['targetAngle'],
            data['value'],
            1.0,
            showPencil: false,
          );
        }
      }
    }
  }

  @override
  void paintAnimated(
    Canvas canvas,
    Size size,
    RoboContext ctx,
    double progress,
  ) {
    if (_effectiveVar != null) {
      dynamic data = ctx.getVar(_effectiveVar!);
      if (data is Map && data['type'] == 'measured_angle') {
        Offset? vertex = ctx.evaluateExpression(data['vertex']);
        if (vertex != null) {
          double pArrive = (progress / 0.15).clamp(0.0, 1.0);
          double pMeasure = ((progress - 0.15) / 0.25).clamp(0.0, 1.0);
          double pClearRot = ((progress - 0.4) / 0.15).clamp(0.0, 1.0);
          double pFadeOut = ((progress - 0.55) / 0.05).clamp(0.0, 1.0);
          double pArc = ((progress - 0.6) / 0.4).clamp(0.0, 1.0);

          Offset center = ctx.gridToPixel(vertex.dx, vertex.dy);

          if (pFadeOut < 1.0) {
            double opacity = 1.0;
            if (pArrive < 0.5) opacity = pArrive / 0.5;
            if (pFadeOut > 0.0) opacity = 1.0 - pFadeOut;

            double easeArrive = sin(pArrive * pi / 2);
            double easeClear = 1.0 - cos(pClearRot * pi / 2);

            double extraRotation =
                (1.0 - easeArrive) * (-pi / 3) + (easeClear) * (-pi / 3);
            double translateY = -easeClear * 60.0;

            paintRealisticProtractor(
              canvas,
              center,
              data['baseAngle'],
              data['targetAngle'],
              data['value'],
              pMeasure,
              opacity: opacity,
              translateY: translateY,
              extraRotation: extraRotation,
              drawArc: true,
            );
          }

          if (progress > 0.4) {
            _paintPencilArc(
              canvas,
              center,
              data['baseAngle'],
              data['targetAngle'],
              data['value'],
              pArc,
            );
          }
        }
      }
    }
  }
}

class RoboPlotCommand extends RoboCommand {
  final String expr;
  final dynamic minRef;
  final dynamic maxRef;

  RoboPlotCommand(
    String rawCommand,
    String? assignedVar,
    this.expr,
    this.minRef,
    this.maxRef,
  ) : super(rawCommand, assignedVar);

  @override
  void evaluate(RoboContext ctx) {
    if (assignedVar == null) return;

    double minX = minRef != null
        ? (minRef is double
              ? minRef
              : (ctx.evaluateExpression(minRef) as double? ?? ctx.minX))
        : ctx.minX;
    double maxX = maxRef != null
        ? (maxRef is double
              ? maxRef
              : (ctx.evaluateExpression(maxRef) as double? ?? ctx.maxX))
        : ctx.maxX;

    String mathStr = expr.replaceAll("'", "").replaceAll('"', '');
    mathStr = mathStr.replaceAllMapped(RegExp(r'\b(sin|cos|tan)\(([^)]+)\)'), (
      Match m,
    ) {
      return '\${m[1]}((\${m[2]}) * 3.141592653589793 / 180.0)';
    });

    try {
      Parser p = Parser();
      Expression exp = p.parse(mathStr);
      ContextModel cm = ContextModel();

      ctx.variables.forEach((key, value) {
        if (value.data is num) {
          cm.bindVariable(
            Variable(key),
            Number((value.data as num).toDouble()),
          );
        }
      });

      List<String> anonPoints = [];
      double step = (maxX - minX) / 100.0;
      if (step <= 0) step = 0.1;

      for (double x = minX; x <= maxX; x += step) {
        cm.bindVariable(Variable('x'), Number(x));
        double y = exp.evaluate(EvaluationType.REAL, cm);
        anonPoints.add(RoboTransformations.generateAnonVar(ctx, Offset(x, y)));
      }

      ctx.setVar(assignedVar!, {'type': 'path', 'points': anonPoints});
    } catch (e) {
      debugPrint("Plot Error: \$e");
    }
  }

  @override
  void paintStatic(Canvas canvas, Size size, RoboContext ctx) {}

  @override
  void paintAnimated(
    Canvas canvas,
    Size size,
    RoboContext ctx,
    double progress,
  ) {}
}

class RoboParaCommand extends RoboCommand {
  final String exprX;
  final String exprY;
  final dynamic minRef;
  final dynamic maxRef;
  final dynamic stepRef;

  RoboParaCommand(
    String rawCommand,
    String? assignedVar,
    this.exprX,
    this.exprY,
    this.minRef,
    this.maxRef,
    this.stepRef,
  ) : super(rawCommand, assignedVar);

  @override
  void evaluate(RoboContext ctx) {
    if (assignedVar == null) return;

    double minT = minRef != null
        ? (minRef is double
              ? minRef
              : (ctx.evaluateExpression(minRef) as double? ?? 0.0))
        : 0.0;
    double maxT = maxRef != null
        ? (maxRef is double
              ? maxRef
              : (ctx.evaluateExpression(maxRef) as double? ?? 360.0))
        : 360.0;
    double stepT = stepRef != null
        ? (stepRef is double
              ? stepRef
              : (ctx.evaluateExpression(stepRef) as double? ?? 5.0))
        : 5.0;

    String strX = exprX.replaceAll("'", "").replaceAll('"', '');
    String strY = exprY.replaceAll("'", "").replaceAll('"', '');

    strX = strX.replaceAllMapped(
      RegExp(r'\b(sin|cos|tan)\(([^)]+)\)'),
      (Match m) => '\${m[1]}((\${m[2]}) * 3.141592653589793 / 180.0)',
    );
    strY = strY.replaceAllMapped(
      RegExp(r'\b(sin|cos|tan)\(([^)]+)\)'),
      (Match m) => '\${m[1]}((\${m[2]}) * 3.141592653589793 / 180.0)',
    );

    try {
      Parser p = Parser();
      Expression expX = p.parse(strX);
      Expression expY = p.parse(strY);
      ContextModel cm = ContextModel();

      ctx.variables.forEach((key, value) {
        if (value.data is num) {
          cm.bindVariable(
            Variable(key),
            Number((value.data as num).toDouble()),
          );
        }
      });

      List<String> anonPoints = [];
      if (stepT <= 0) stepT = 1.0;

      for (double t = minT; t <= maxT; t += stepT) {
        cm.bindVariable(Variable('t'), Number(t));
        double x = expX.evaluate(EvaluationType.REAL, cm);
        double y = expY.evaluate(EvaluationType.REAL, cm);
        anonPoints.add(RoboTransformations.generateAnonVar(ctx, Offset(x, y)));
      }

      ctx.setVar(assignedVar!, {'type': 'path', 'points': anonPoints});
    } catch (e) {
      debugPrint("Para Error: \$e");
    }
  }

  @override
  void paintStatic(Canvas canvas, Size size, RoboContext ctx) {}

  @override
  void paintAnimated(
    Canvas canvas,
    Size size,
    RoboContext ctx,
    double progress,
  ) {}
}

class RoboTraceCommand extends RoboCommand {
  final List<dynamic> pointRefs;

  RoboTraceCommand(String rawCommand, String? assignedVar, this.pointRefs)
    : super(rawCommand, assignedVar);

  @override
  void evaluate(RoboContext ctx) {
    if (assignedVar == null) return;

    List<String> anonPoints = [];
    for (dynamic pref in pointRefs) {
      Offset? p = ctx.evaluateExpression(pref);
      if (p != null) {
        anonPoints.add(RoboTransformations.generateAnonVar(ctx, p));
      }
    }

    ctx.setVar(assignedVar!, {'type': 'path', 'points': anonPoints});
  }

  @override
  void paintStatic(Canvas canvas, Size size, RoboContext ctx) {}

  @override
  void paintAnimated(
    Canvas canvas,
    Size size,
    RoboContext ctx,
    double progress,
  ) {}
}

class RoboPartCommand extends RoboCommand {
  final dynamic shapeRef;
  final dynamic pt1Ref;
  final dynamic pt2Ref;
  final dynamic indexRef;

  RoboPartCommand(
    String rawCommand,
    String? assignedVar,
    this.shapeRef,
    this.pt1Ref,
    this.pt2Ref,
    this.indexRef,
  ) : super(rawCommand, assignedVar);

  @override
  void evaluate(RoboContext ctx) {
    if (assignedVar == null) return;

    dynamic shape = ctx.evaluateExpression(shapeRef);
    Offset? p1 = ctx.evaluateExpression(pt1Ref);
    Offset? p2 = ctx.evaluateExpression(pt2Ref);

    if (shape is Map && p1 != null && p2 != null) {
      if (shape['type'] == 'line' ||
          shape['type'] == 'polygon' ||
          shape['type'] == 'path') {
        String anon1 = RoboTransformations.generateAnonVar(ctx, p1);
        String anon2 = RoboTransformations.generateAnonVar(ctx, p2);
        ctx.setVar(assignedVar!, {'type': 'line', 'p1': anon1, 'p2': anon2});
      }
    }
  }

  @override
  void paintStatic(Canvas canvas, Size size, RoboContext ctx) {}

  @override
  void paintAnimated(
    Canvas canvas,
    Size size,
    RoboContext ctx,
    double progress,
  ) {}
}

class RoboFillCommand extends RoboCommand {
  final List<dynamic> targets;

  RoboFillCommand(String rawCommand, String? assignedVar, this.targets)
    : super(rawCommand, assignedVar);

  @override
  void evaluate(RoboContext ctx) {
    for (dynamic target in targets) {
      String? label;
      if (target is String) {
        label = target;
      }

      if (label != null) {
        RoboObject? obj = ctx.getObject(label);
        if (obj != null) {
          obj.isFilled = true;
        } else {
          dynamic result = ctx.evaluateExpression(label);
          if (result != null) {
            RoboObject? anonObj = ctx.getObject(label);
            if (anonObj != null) {
              anonObj.isFilled = true;
            }
          }
        }
      }
    }
  }

  @override
  void paintStatic(Canvas canvas, Size size, RoboContext ctx) {}

  @override
  void paintAnimated(
    Canvas canvas,
    Size size,
    RoboContext ctx,
    double progress,
  ) {}
}

class RoboBooleanCommand extends RoboCommand {
  final String op; // 'and', 'or', 'diff'
  final List<dynamic> args;

  RoboBooleanCommand(String rawCommand, String? assignedVar, this.op, this.args)
    : super(rawCommand, assignedVar);

  @override
  void evaluate(RoboContext ctx) {
    if (assignedVar == null || args.length < 2) return;

    String currentVar = args[0] is String
        ? args[0]
        : RoboTransformations.generateAnonVar(ctx, args[0]);

    for (int i = 1; i < args.length; i++) {
      String nextVar = args[i] is String
          ? args[i]
          : RoboTransformations.generateAnonVar(ctx, args[i]);

      Map<String, dynamic> region = {
        'type': 'region',
        'operation': op,
        's1': currentVar,
        's2': nextVar,
      };

      if (i == args.length - 1) {
        ctx.setVar(assignedVar!, region);
      } else {
        currentVar = RoboTransformations.generateAnonVar(ctx, region);
      }
    }
  }

  @override
  void paintStatic(Canvas canvas, Size size, RoboContext ctx) {}

  @override
  void paintAnimated(
    Canvas canvas,
    Size size,
    RoboContext ctx,
    double progress,
  ) {}
}
