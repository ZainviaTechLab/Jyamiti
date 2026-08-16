import 'package:flutter/material.dart';
import 'package:math_expressions/math_expressions.dart';
import 'instrument_models.dart';

class GraphWidget extends StatefulWidget {
  final GraphState state;
  final VoidCallback onStateChanged;

  const GraphWidget({
    super.key,
    required this.state,
    required this.onStateChanged,
  });

  @override
  State<GraphWidget> createState() => _GraphWidgetState();
}

class _GraphWidgetState extends State<GraphWidget> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.state.equation);
  }

  @override
  void didUpdateWidget(covariant GraphWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.equation != widget.state.equation) {
      if (_controller.text != widget.state.equation) {
        _controller.text = widget.state.equation;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateEquation(String val) {
    widget.state.equation = val;
    widget.onStateChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.state.pivot.dx - widget.state.widthPx / 2,
      top: widget.state.pivot.dy - widget.state.heightPx / 2,
      child: Transform.rotate(
        angle: widget.state.rotation,
        child: Container(
          width: widget.state.widthPx,
          height: widget.state.heightPx,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 10,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Equation Input Header
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                  border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                ),
                child: Row(
                  children: [
                    const Text(
                      'f(x) = ',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        onChanged: _updateEquation,
                        style: const TextStyle(fontSize: 16, fontFamily: 'monospace', color: Colors.black87),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Plot Area
              Expanded(
                child: ClipRect(
                  child: CustomPaint(
                    painter: _GraphPainter(widget.state),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  final GraphState state;

  _GraphPainter(this.state);

  @override
  void paint(Canvas canvas, Size size) {
    // Draw Grid and Axes
    final gridPaint = Paint()..color = Colors.grey.shade200..strokeWidth = 1;
    final axesPaint = Paint()..color = Colors.black54..strokeWidth = 2;

    double xRange = state.xMax - state.xMin;
    double yRange = state.yMax - state.yMin;

    if (xRange <= 0 || yRange <= 0) return;

    // Convert data coordinate (x,y) to pixel coordinate (px,py)
    Offset toPixel(double x, double y) {
      double px = (x - state.xMin) / xRange * size.width;
      double py = size.height - (y - state.yMin) / yRange * size.height;
      return Offset(px, py);
    }

    // Draw vertical grid lines
    int startX = state.xMin.floor();
    int endX = state.xMax.ceil();
    for (int i = startX; i <= endX; i++) {
      double px = toPixel(i.toDouble(), 0).dx;
      canvas.drawLine(Offset(px, 0), Offset(px, size.height), i == 0 ? axesPaint : gridPaint);
    }

    // Draw horizontal grid lines
    int startY = state.yMin.floor();
    int endY = state.yMax.ceil();
    for (int i = startY; i <= endY; i++) {
      double py = toPixel(0, i.toDouble()).dy;
      canvas.drawLine(Offset(0, py), Offset(size.width, py), i == 0 ? axesPaint : gridPaint);
    }

    // Parse and Plot Equation
    if (state.equation.trim().isEmpty) return;

    try {
      Parser p = Parser();
      Expression exp = p.parse(state.equation.replaceAll(' ', ''));
      ContextModel cm = ContextModel();

      Path path = Path();
      bool first = true;

      // Sample points
      int samples = size.width.toInt();
      for (int i = 0; i <= samples; i++) {
        double px = i.toDouble();
        double x = state.xMin + (px / size.width) * xRange;

        cm.bindVariable(Variable('x'), Number(x));
        double y = exp.evaluate(EvaluationType.REAL, cm);

        if (y.isNaN || y.isInfinite) {
          first = true;
          continue;
        }

        double py = size.height - (y - state.yMin) / yRange * size.height;
        
        // Don't draw lines connecting points across vertical asymptotes
        if (!first && (py < -size.height * 2 || py > size.height * 3)) {
           first = true;
           continue;
        }

        if (first) {
          path.moveTo(px, py);
          first = false;
        } else {
          path.lineTo(px, py);
        }
      }

      final plotPaint = Paint()
        ..color = Colors.blue
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;

      canvas.drawPath(path, plotPaint);
    } catch (e) {
      // Parse error, just don't draw the line
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) {
    return oldDelegate.state.equation != state.equation ||
           oldDelegate.state.widthPx != state.widthPx ||
           oldDelegate.state.heightPx != state.heightPx ||
           oldDelegate.state.xMin != state.xMin ||
           oldDelegate.state.xMax != state.xMax ||
           oldDelegate.state.yMin != state.yMin ||
           oldDelegate.state.yMax != state.yMax;
  }
}
