import 'package:flutter/material.dart';
import '../models/robo_command.dart';
import '../models/robo_context.dart';

class RoboCanvas extends StatelessWidget {
  final RoboContext ctx;
  final List<RoboCommand> commands;
  final int activeCommandIndex;
  final double animationProgress;

  const RoboCanvas({
    Key? key,
    required this.ctx,
    required this.commands,
    required this.activeCommandIndex,
    required this.animationProgress,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _RoboPainter(
            ctx: ctx,
            commands: commands,
            activeCommandIndex: activeCommandIndex,
            animationProgress: animationProgress,
          ),
        );
      },
    );
  }
}

class _RoboPainter extends CustomPainter {
  final RoboContext ctx;
  final List<RoboCommand> commands;
  final int activeCommandIndex;
  final double animationProgress;

  _RoboPainter({
    required this.ctx,
    required this.commands,
    required this.activeCommandIndex,
    required this.animationProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _updateGridToPixel(size);
    _drawGrid(canvas, size);

    // 1. Draw all completed commands
    for (int i = 0; i < activeCommandIndex && i < commands.length; i++) {
      commands[i].paintStatic(canvas, size, ctx);
    }

    // 2. Draw the currently animating command
    if (activeCommandIndex >= 0 && activeCommandIndex < commands.length) {
      commands[activeCommandIndex].paintAnimated(canvas, size, ctx, animationProgress);
    }
  }

  void _updateGridToPixel(Size size) {
    // Maintain a 1:1 aspect ratio. Keep the smaller dimension covering 40 units.
    double baseRange = 40.0;
    
    if (size.width > size.height) {
      double scale = size.height / baseRange;
      double xRange = size.width / scale;
      ctx.minY = -baseRange / 2;
      ctx.maxY = baseRange / 2;
      ctx.minX = -xRange / 2;
      ctx.maxX = xRange / 2;
    } else {
      double scale = size.width / baseRange;
      double yRange = size.height / scale;
      ctx.minX = -baseRange / 2;
      ctx.maxX = baseRange / 2;
      ctx.minY = -yRange / 2;
      ctx.maxY = yRange / 2;
    }

    ctx.gridToPixel = (x, y) {
      double xRange = ctx.maxX - ctx.minX;
      double yRange = ctx.maxY - ctx.minY;
      
      double px = (x - ctx.minX) / xRange * size.width;
      // Invert Y axis so positive is up
      double py = size.height - (y - ctx.minY) / yRange * size.height;
      return Offset(px, py);
    };
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()..color = Colors.grey.shade300..strokeWidth = 1;
    final axesPaint = Paint()..color = Colors.black87..strokeWidth = 2;

    int startX = ctx.minX.floor();
    int endX = ctx.maxX.ceil();
    for (int i = startX; i <= endX; i++) {
      double px = ctx.gridToPixel(i.toDouble(), 0).dx;
      canvas.drawLine(Offset(px, 0), Offset(px, size.height), i == 0 ? axesPaint : gridPaint);
      if (i != 0 && i % 2 == 0) {
        _drawText(canvas, i.toString(), Offset(px, ctx.gridToPixel(0, 0).dy + 5));
      }
    }

    int startY = ctx.minY.floor();
    int endY = ctx.maxY.ceil();
    for (int i = startY; i <= endY; i++) {
      double py = ctx.gridToPixel(0, i.toDouble()).dy;
      canvas.drawLine(Offset(0, py), Offset(size.width, py), i == 0 ? axesPaint : gridPaint);
      if (i != 0 && i % 2 == 0) {
        _drawText(canvas, i.toString(), Offset(ctx.gridToPixel(0, 0).dx - 20, py - 8));
      }
    }

    _drawText(canvas, "0", Offset(ctx.gridToPixel(0, 0).dx - 15, ctx.gridToPixel(0, 0).dy + 5));
  }

  void _drawText(Canvas canvas, String text, Offset position) {
    TextSpan span = TextSpan(style: const TextStyle(color: Colors.black54, fontSize: 12), text: text);
    TextPainter tp = TextPainter(text: span, textAlign: TextAlign.center, textDirection: TextDirection.ltr);
    tp.layout();
    tp.paint(canvas, position);
  }

  @override
  bool shouldRepaint(covariant _RoboPainter oldDelegate) {
    return oldDelegate.animationProgress != animationProgress ||
           oldDelegate.activeCommandIndex != activeCommandIndex ||
           oldDelegate.commands != commands;
  }
}
