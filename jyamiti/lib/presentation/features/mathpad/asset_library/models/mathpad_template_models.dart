import 'dart:math';

import 'package:flutter/material.dart' show Offset, Color;

import '../../screens/mathpad.dart';

/// A bundled 2D diagram preset for the Asset Library's Templates tab.
/// [buildLines]/[buildLabels] are factories (not stored lists) so every
/// insertion mints fresh `MathsPadLine`/`MathsPadTextLabel`/
/// `MathsPadStrokePoint` instances -- otherwise two inserted copies of the
/// same template would share mutable point lists and moving one would drag
/// the other with it.
///
/// Every template is authored in a local coordinate space centered on
/// `Offset.zero`; `_insertTemplate` in `mathpad.dart` translates every
/// point by the viewport center at insertion time.
class MathPadTemplate {
  final String id;
  final String name;
  final List<MathsPadLine> Function() buildLines;
  final List<MathsPadTextLabel> Function() buildLabels;

  const MathPadTemplate({
    required this.id,
    required this.name,
    required this.buildLines,
    this.buildLabels = _noLabels,
  });

  static List<MathsPadTextLabel> _noLabels() => [];
}

const Color _kTemplateStrokeColor = Color(0xFF6366F1);
const Color _kTemplateAxisColor = Color(0xFF64748B);
const double _kTemplateStrokeWidth = 2.5;

List<Offset> _regularPolygonPoints(int sides, double radius, {double startAngle = -pi / 2}) {
  final points = <Offset>[];
  for (int i = 0; i <= sides; i++) {
    final a = startAngle + (2 * pi * i / sides);
    points.add(Offset(cos(a), sin(a)) * radius);
  }
  return points;
}

List<Offset> _circlePoints(double radius, {int steps = 72}) {
  final points = <Offset>[];
  for (int i = 0; i <= steps; i++) {
    final a = 2 * pi * i / steps;
    points.add(Offset(cos(a), sin(a)) * radius);
  }
  return points;
}

MathsPadLine _shapeLine(List<Offset> points, {Color color = _kTemplateStrokeColor}) {
  return MathsPadLine(
    points: points.map(MathsPadStrokePoint.new).toList(),
    color: color,
    strokeWidth: _kTemplateStrokeWidth,
    isShape: true,
  );
}

final MathPadTemplate _triangleTemplate = MathPadTemplate(
  id: 'triangle',
  name: 'Triangle',
  buildLines: () => [_shapeLine(_regularPolygonPoints(3, 70))],
);

final MathPadTemplate _circleWithRadiusTemplate = MathPadTemplate(
  id: 'circleWithRadius',
  name: 'Circle + Radius',
  buildLines: () => [
    _shapeLine(_circlePoints(70)),
    MathsPadLine(
      points: [
        MathsPadStrokePoint(Offset.zero),
        MathsPadStrokePoint(const Offset(70, 0)),
      ],
      color: _kTemplateStrokeColor,
      strokeWidth: _kTemplateStrokeWidth,
    ),
  ],
  buildLabels: () => [
    MathsPadTextLabel(position: const Offset(28, -22), text: 'r', color: _kTemplateStrokeColor, fontSize: 18),
  ],
);

final MathPadTemplate _axesTemplate = MathPadTemplate(
  id: 'coordinateAxes',
  name: 'Coordinate Axes',
  buildLines: () {
    const double reach = 150;
    const double tickSpacing = 25;
    const double tickHalf = 4;
    final lines = <MathsPadLine>[
      MathsPadLine(
        points: [MathsPadStrokePoint(const Offset(-reach, 0)), MathsPadStrokePoint(const Offset(reach, 0))],
        color: _kTemplateAxisColor,
        strokeWidth: _kTemplateStrokeWidth,
      ),
      MathsPadLine(
        points: [MathsPadStrokePoint(const Offset(0, -reach)), MathsPadStrokePoint(const Offset(0, reach))],
        color: _kTemplateAxisColor,
        strokeWidth: _kTemplateStrokeWidth,
      ),
    ];
    for (double x = -reach + tickSpacing; x < reach; x += tickSpacing) {
      if (x.abs() < 1) continue;
      lines.add(MathsPadLine(
        points: [MathsPadStrokePoint(Offset(x, -tickHalf)), MathsPadStrokePoint(Offset(x, tickHalf))],
        color: _kTemplateAxisColor,
        strokeWidth: 1.5,
      ));
    }
    for (double y = -reach + tickSpacing; y < reach; y += tickSpacing) {
      if (y.abs() < 1) continue;
      lines.add(MathsPadLine(
        points: [MathsPadStrokePoint(Offset(-tickHalf, y)), MathsPadStrokePoint(Offset(tickHalf, y))],
        color: _kTemplateAxisColor,
        strokeWidth: 1.5,
      ));
    }
    return lines;
  },
  buildLabels: () => [
    MathsPadTextLabel(position: const Offset(140, 10), text: 'x', color: _kTemplateAxisColor, fontSize: 16),
    MathsPadTextLabel(position: const Offset(6, -148), text: 'y', color: _kTemplateAxisColor, fontSize: 16),
  ],
);

final MathPadTemplate _numberLineTemplate = MathPadTemplate(
  id: 'numberLine',
  name: 'Number Line',
  buildLines: () {
    const double reach = 150;
    const double tickSpacing = 30;
    const double tickHalf = 6;
    final lines = <MathsPadLine>[
      MathsPadLine(
        points: [MathsPadStrokePoint(const Offset(-reach, 0)), MathsPadStrokePoint(const Offset(reach, 0))],
        color: _kTemplateAxisColor,
        strokeWidth: _kTemplateStrokeWidth,
      ),
    ];
    for (double x = -reach; x <= reach + 0.01; x += tickSpacing) {
      lines.add(MathsPadLine(
        points: [MathsPadStrokePoint(Offset(x, -tickHalf)), MathsPadStrokePoint(Offset(x, tickHalf))],
        color: _kTemplateAxisColor,
        strokeWidth: 1.8,
      ));
    }
    return lines;
  },
  buildLabels: () => [
    MathsPadTextLabel(position: const Offset(-6, 12), text: '0', color: _kTemplateAxisColor, fontSize: 14),
  ],
);

/// All bundled Templates-tab presets, in display order.
final List<MathPadTemplate> kPresetTemplates = [
  _triangleTemplate,
  _circleWithRadiusTemplate,
  _axesTemplate,
  _numberLineTemplate,
];
