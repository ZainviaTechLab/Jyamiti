import 'package:flutter/material.dart';
import '../models/robo_command.dart';
import '../models/robo_context.dart';

class RoboCanvas extends StatelessWidget {
  final RoboContext ctx;
  final List<RoboCommand> commands;
  final int activeCommandIndex;
  final double animationProgress;
  final bool showGrid;
  final bool isDarkMode;

  const RoboCanvas({
    Key? key,
    required this.ctx,
    required this.commands,
    required this.activeCommandIndex,
    required this.animationProgress,
    this.showGrid = true,
    this.isDarkMode = false,
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
            showGrid: showGrid,
            isDarkMode: isDarkMode,
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
  final bool showGrid;
  final bool isDarkMode;

  _RoboPainter({
    required this.ctx,
    required this.commands,
    required this.activeCommandIndex,
    required this.animationProgress,
    required this.showGrid,
    required this.isDarkMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    ctx.isDarkMode = isDarkMode;
    _updateGridToPixel(size);
    
    if (showGrid) {
      _drawGrid(canvas, size);
    }

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
    double br = ctx.baseRange;
    
    if (size.width > size.height) {
      double scale = size.height / br;
      double xRange = size.width / scale;
      ctx.minY = ctx.cy - br / 2;
      ctx.maxY = ctx.cy + br / 2;
      ctx.minX = ctx.cx - xRange / 2;
      ctx.maxX = ctx.cx + xRange / 2;
    } else {
      double scale = size.width / br;
      double yRange = size.height / scale;
      ctx.minX = ctx.cx - br / 2;
      ctx.maxX = ctx.cx + br / 2;
      ctx.minY = ctx.cy - yRange / 2;
      ctx.maxY = ctx.cy + yRange / 2;
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
    final gridColor = isDarkMode ? Colors.grey.shade800 : Colors.grey.shade300;
    final axesColor = isDarkMode ? Colors.white54 : Colors.black87;
    final textColor = isDarkMode ? Colors.white54 : Colors.black54;

    final gridPaint = Paint()..color = gridColor..strokeWidth = 1;
    final axesPaint = Paint()..color = axesColor..strokeWidth = 2;

    int startX = ctx.minX.floor();
    int endX = ctx.maxX.ceil();
    for (int i = startX; i <= endX; i++) {
      double px = ctx.gridToPixel(i.toDouble(), 0).dx;
      canvas.drawLine(Offset(px, 0), Offset(px, size.height), i == 0 ? axesPaint : gridPaint);
      if (i != 0 && i % 2 == 0) {
        _drawText(canvas, i.toString(), Offset(px, ctx.gridToPixel(0, 0).dy + 5), textColor);
      }
    }

    int startY = ctx.minY.floor();
    int endY = ctx.maxY.ceil();
    for (int i = startY; i <= endY; i++) {
      double py = ctx.gridToPixel(0, i.toDouble()).dy;
      canvas.drawLine(Offset(0, py), Offset(size.width, py), i == 0 ? axesPaint : gridPaint);
      if (i != 0 && i % 2 == 0) {
        _drawText(canvas, i.toString(), Offset(ctx.gridToPixel(0, 0).dx - 20, py - 8), textColor);
      }
    }

    _drawText(canvas, "0", Offset(ctx.gridToPixel(0, 0).dx - 15, ctx.gridToPixel(0, 0).dy + 5), textColor);
  }

  void _drawText(Canvas canvas, String text, Offset position, Color textColor) {
    TextSpan span = TextSpan(style: TextStyle(color: textColor, fontSize: 12), text: text);
    TextPainter tp = TextPainter(text: span, textAlign: TextAlign.center, textDirection: TextDirection.ltr);
    tp.layout();
    tp.paint(canvas, position);
  }

  @override
  bool shouldRepaint(covariant _RoboPainter oldDelegate) {
    return oldDelegate.animationProgress != animationProgress ||
           oldDelegate.activeCommandIndex != activeCommandIndex ||
           oldDelegate.commands != commands ||
           oldDelegate.showGrid != showGrid ||
           oldDelegate.isDarkMode != isDarkMode;
  }
}
