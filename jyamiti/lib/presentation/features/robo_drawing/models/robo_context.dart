import 'dart:ui';
import 'package:math_expressions/math_expressions.dart';
import '../parser/robo_parser.dart';
import '../models/robo_command.dart';

class RoboObject {
  final dynamic data;
  bool isHidden = false;
  double opacity = 1.0;
  double strokeWidth = 2.0;
  bool isFilled = false; // New property for boolean operations and fill

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
        ..strokeWidth = variables[name]!.strokeWidth;
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
    if (expr is! String) return expr;

    // Check if it's a known variable
    if (variables.containsKey(expr)) {
      return variables[expr]?.data;
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
