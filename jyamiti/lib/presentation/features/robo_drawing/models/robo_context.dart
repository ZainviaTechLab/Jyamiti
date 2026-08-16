import 'package:flutter/material.dart';
import 'package:math_expressions/math_expressions.dart';
import '../parser/robo_parser.dart';
import '../models/robo_command.dart';

class RoboObject {
  final dynamic data;
  bool isHidden = false;
  double opacity = 1.0;
  double strokeWidth = 2.0;
  bool isFilled = false; // New property for boolean operations and fill
  
  // UI Settings properties
  Color color = Colors.blue;
  bool showLabel = true;
  double labelOffsetX = 5.0;
  double labelOffsetY = 5.0;
  double? speedOverride;
  String? comment;

  RoboObject(this.data);
}

/// Stores the current execution state and variables for the Robo Drawing canvas.
class RoboContext {
  /// Maps variable names (e.g., 'A', 'line1') to evaluated geometric objects.
  final Map<String, RoboObject> variables = {};

  int _anonCounter = 0;

  /// Converts a grid coordinate (e.g. 3, 3) to a physical pixel coordinate
  Offset Function(double x, double y) gridToPixel = (x, y) => Offset(x, y);
  
  /// The bounds of the current grid view (minX, maxX, minY, maxY)
  double minX = -20;
  double maxX = 20;
  double minY = -20;
  double maxY = 20;

  String currentPointType = 'sphere'; // or 'cross'
  bool isDarkMode = false;

  double cx = 0;
  double cy = 0;
  double baseRange = 40.0;

  void updateBoundingBox() {
    double minXVal = double.infinity;
    double maxXVal = -double.infinity;
    double minYVal = double.infinity;
    double maxYVal = -double.infinity;

    void addPoint(Offset p) {
      if (p.dx < minXVal) minXVal = p.dx;
      if (p.dx > maxXVal) maxXVal = p.dx;
      if (p.dy < minYVal) minYVal = p.dy;
      if (p.dy > maxYVal) maxYVal = p.dy;
    }

    for (var obj in variables.values) {
      if (obj.isHidden) continue;
      var data = obj.data;
      if (data is Offset) {
        addPoint(data);
      } else if (data is Map) {
        if (data['type'] == 'line' || data['type'] == 'dash') {
          var p1 = evaluateExpression(data['p1']);
          var p2 = evaluateExpression(data['p2']);
          if (p1 is Offset) addPoint(p1);
          if (p2 is Offset) addPoint(p2);
        } else if (data['type'] == 'circle' || data['type'] == 'arc') {
          var center = evaluateExpression(data['center']);
          var radius = evaluateExpression(data['radius']);
          if (center is Offset && radius is double) {
            addPoint(Offset(center.dx - radius, center.dy - radius));
            addPoint(Offset(center.dx + radius, center.dy + radius));
          }
        } else if (data['type'] == 'polygon' || data['type'] == 'path') {
          var pts = data['points'];
          if (pts is List) {
            for (var ptRef in pts) {
              var p = evaluateExpression(ptRef);
              if (p is Offset) addPoint(p);
            }
          }
        }
      }
    }

    if (minXVal == double.infinity) {
      cx = 0;
      cy = 0;
      baseRange = 40.0;
    } else {
      cx = (minXVal + maxXVal) / 2;
      cy = (minYVal + maxYVal) / 2;
      double w = maxXVal - minXVal;
      double h = maxYVal - minYVal;
      baseRange = (w > h ? w : h) * 1.5; // 50% padding
      if (baseRange < 10) baseRange = 10;
    }
  }

  void clear() {
    variables.clear();
    currentPointType = 'sphere';
    _anonCounter = 0;
  }

  void setVar(String name, dynamic data) {
    if (variables.containsKey(name)) {
      variables[name] = RoboObject(data)
        ..isHidden = variables[name]!.isHidden
        ..opacity = variables[name]!.opacity
        ..strokeWidth = variables[name]!.strokeWidth
        ..isFilled = variables[name]!.isFilled
        ..color = variables[name]!.color
        ..showLabel = variables[name]!.showLabel
        ..labelOffsetX = variables[name]!.labelOffsetX
        ..labelOffsetY = variables[name]!.labelOffsetY
        ..speedOverride = variables[name]!.speedOverride
        ..comment = variables[name]!.comment;
    } else {
      variables[name] = RoboObject(data);
    }
  }

  RoboObject? getObject(String name) {
    return variables[name];
  }

  dynamic getVar(String name) {
    return variables[name]?.data;
  }

  dynamic evaluateExpression(dynamic expr) {
    if (expr is double) return expr;
    if (expr is Map && expr['type'] == 'point') {
      double px = expr['x'] is double ? expr['x'] : (evaluateExpression(expr['x']) as double? ?? 0.0);
      double py = expr['y'] is double ? expr['y'] : (evaluateExpression(expr['y']) as double? ?? 0.0);
      return Offset(px, py);
    }
    if (expr is! String) return expr;

    // Check if it's a known variable
    if (variables.containsKey(expr)) {
      var data = variables[expr]?.data;
      if (data is Map && data['type'] == 'measured_angle') {
        return data['value'];
      }
      return data;
    }

    // Check if it's a raw number
    double? numVal = double.tryParse(expr);
    if (numVal != null) return numVal;

    // Try math_expressions
    try {
      String mathStr = expr;
      // Convert degrees to radians for trig functions
      mathStr = mathStr.replaceAllMapped(RegExp(r'\b(sin|cos|tan)\(([^)]+)\)'), (Match m) {
        return '\${m[1]}((\${m[2]}) * 3.141592653589793 / 180.0)';
      });
      
      Parser p = Parser();
      Expression exp = p.parse(mathStr);
      ContextModel cm = ContextModel();
      // Bind known numeric variables
      variables.forEach((key, value) {
        if (value.data is num) {
          cm.bindVariable(Variable(key), Number((value.data as num).toDouble()));
        } else if (value.data is Map && value.data['type'] == 'measured_angle') {
          cm.bindVariable(Variable(key), Number((value.data['value'] as num).toDouble()));
        }
      });
      double res = exp.evaluate(EvaluationType.REAL, cm);
      return res;
    } catch (e) {
      // Not a valid algebraic expression, continue to command parsing
    }

    // Otherwise, parse it as an inline command!
    _anonCounter++;
    String anonVar = '_anon$_anonCounter';
    RoboCommand? cmd = RoboParser.parse('$anonVar=$expr');
    if (cmd != null) {
      cmd.evaluate(this);
      // Mark it hidden so it doesn't render statically on its own unless intended
      if (variables.containsKey(anonVar)) {
        variables[anonVar]!.isHidden = true;
      }
      return getVar(anonVar);
    }

    return null;
  }
}
