import 'dart:math';
import 'package:flutter/material.dart';
import 'robo_context.dart';

class RoboTransformations {
  static int _anonCounter = 0;

  static String generateAnonVar(RoboContext ctx, dynamic data) {
    _anonCounter++;
    String name = '_anon$_anonCounter';
    ctx.setVar(name, data);
    ctx.variables[name]!.isHidden = true; // Anon variables shouldn't be drawn individually
    return name;
  }

  /// Applies a generic transformation function to a geometric object (point, line, circle, arc, polygon, group)
  static dynamic applyTransform(RoboContext ctx, dynamic data, Offset Function(Offset) transformFunc, {double rotateAngleDeg = 0}) {
    if (data is Offset) {
      return transformFunc(data);
    }
    
    if (data is Map) {
      String type = data['type'];
      if (type == 'line') {
        Offset? p1 = ctx.evaluateExpression(data['p1']);
        Offset? p2 = ctx.evaluateExpression(data['p2']);
        if (p1 == null || p2 == null) return null;
        
        return {
          'type': 'line',
          'p1': generateAnonVar(ctx, transformFunc(p1)),
          'p2': generateAnonVar(ctx, transformFunc(p2)),
        };
      } else if (type == 'polygon') {
        List<dynamic> points = data['points'];
        List<String> newPoints = [];
        for (String pVar in points) {
          Offset? p = ctx.evaluateExpression(pVar);
          if (p != null) {
            newPoints.add(generateAnonVar(ctx, transformFunc(p)));
          }
        }
        return {'type': 'polygon', 'points': newPoints};
      } else if (type == 'circle') {
        Offset? center = ctx.evaluateExpression(data['center']);
        if (center == null) return null;
        
        return {
          'type': 'circle',
          'center': generateAnonVar(ctx, transformFunc(center)),
          'radius': data['radius'], 
        };
      } else if (type == 'arc') {
        Offset? center = ctx.evaluateExpression(data['center']);
        if (center == null) return null;
        
        double oldStart = data['start'] is double ? data['start'] : (ctx.evaluateExpression(data['start']) as double? ?? 0.0);
        double newStart = oldStart + rotateAngleDeg;
        
        return {
          'type': 'arc',
          'center': generateAnonVar(ctx, transformFunc(center)),
          'radius': data['radius'],
          'start': newStart,
          'sweep': data['sweep'],
        };
      } else if (type == 'group') {
        List<dynamic> items = data['items'];
        List<String> newItems = [];
        for (String itemVar in items) {
          dynamic itemData = ctx.evaluateExpression(itemVar);
          if (itemData != null) {
            dynamic transformedData = applyTransform(ctx, itemData, transformFunc, rotateAngleDeg: rotateAngleDeg);
            newItems.add(generateAnonVar(ctx, transformedData));
          }
        }
        return {'type': 'group', 'items': newItems};
      }
    }
    return null;
  }

  static dynamic rotate(RoboContext ctx, dynamic data, double angleDeg, Offset origin) {
    double angleRad = angleDeg * pi / 180.0;
    double cosA = cos(angleRad);
    double sinA = sin(angleRad);

    return applyTransform(ctx, data, (Offset p) {
      double dx = p.dx - origin.dx;
      double dy = p.dy - origin.dy;
      double rx = dx * cosA - dy * sinA;
      double ry = dx * sinA + dy * cosA;
      return Offset(origin.dx + rx, origin.dy + ry);
    }, rotateAngleDeg: angleDeg);
  }

  static dynamic translate(RoboContext ctx, dynamic data, double tx, double ty) {
    return applyTransform(ctx, data, (Offset p) {
      return Offset(p.dx + tx, p.dy + ty);
    });
  }

  static dynamic dilate(RoboContext ctx, dynamic data, double scale, Offset origin) {
    dynamic result = applyTransform(ctx, data, (Offset p) {
      double dx = p.dx - origin.dx;
      double dy = p.dy - origin.dy;
      return Offset(origin.dx + dx * scale, origin.dy + dy * scale);
    });
    
    _scaleRadius(ctx, result, scale);
    return result;
  }
  
  static void _scaleRadius(RoboContext ctx, dynamic data, double scale) {
    if (data is Map) {
      if (data['type'] == 'circle' || data['type'] == 'arc') {
        double r = data['radius'] is double ? data['radius'] : (ctx.getVar(data['radius']) as double? ?? 0.0);
        data['radius'] = (r * scale).abs(); // radius must be positive
      } else if (data['type'] == 'group') {
        for (String itemVar in data['items']) {
          _scaleRadius(ctx, ctx.getVar(itemVar), scale);
        }
      }
    }
  }

  static dynamic reflect(RoboContext ctx, dynamic data, Offset lineP1, Offset lineP2) {
    double dx = lineP2.dx - lineP1.dx;
    double dy = lineP2.dy - lineP1.dy;
    double a = (dx * dx - dy * dy) / (dx * dx + dy * dy);
    double b = 2 * dx * dy / (dx * dx + dy * dy);

    return applyTransform(ctx, data, (Offset p) {
      double px = p.dx - lineP1.dx;
      double py = p.dy - lineP1.dy;
      double rx = a * px + b * py;
      double ry = b * px - a * py;
      return Offset(rx + lineP1.dx, ry + lineP1.dy);
    });
  }
}
