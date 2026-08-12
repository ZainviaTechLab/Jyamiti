import 'dart:math';
import 'package:flutter/material.dart' show Offset;

/// Approximate px-per-cm conversion shared by every instrument, so a given
/// "radius in cm" (compass) or tick spacing (ruler/set square) renders
/// consistently across the canvas regardless of pan/zoom.
const double kPxPerCm = 37.8;

/// Base state for every draggable/rotatable Math Pad instrument.
///
/// All positions here are in canvas WORLD coordinates (the same space as
/// [MathsPadLine] points) — the instrument overlay layer applies the
/// canvas's pan/zoom transform once for the whole layer, so instruments
/// stay attached to the drawing plane as the user pans/zooms.
abstract class InstrumentState {
  Offset pivot;
  double rotation; // radians

  InstrumentState({required this.pivot, this.rotation = 0});

  /// World-space straight edges this instrument offers for snapped line
  /// drawing (ruler: 1 edge; set square: 3 edges; protractor: its flat base).
  List<(Offset, Offset)> strokeableEdges() => const [];

  /// World-space positions of this instrument's drag handles, keyed by role
  /// ("move", "rotate", "resize", or the compass's "pivot"/"hinge"/"tip").
  /// Shared by the widget (for drawing the handle icons) and the canvas's
  /// centralized gesture hit-testing (for dragging them) so both always
  /// agree on exactly where a handle currently is.
  Map<String, Offset> handleWorldPositions() => const {};

  /// Rotates a point local to the instrument's own (unrotated) coordinate
  /// space by [rotation] and translates it to world space around [pivot].
  Offset rotatedLocal(double lx, double ly) {
    final cosR = cos(rotation);
    final sinR = sin(rotation);
    return pivot + Offset(lx * cosR - ly * sinR, lx * sinR + ly * cosR);
  }

  /// Inverse of [rotatedLocal]: converts a world-space point back into this
  /// instrument's own (unrotated) local coordinate space.
  Offset worldToLocal(Offset worldPoint) {
    final rel = worldPoint - pivot;
    final cosR = cos(rotation);
    final sinR = sin(rotation);
    return Offset(
      rel.dx * cosR + rel.dy * sinR,
      -rel.dx * sinR + rel.dy * cosR,
    );
  }
}

/// Half the ruler body's drawn thickness (must match `_RulerPainter`'s
/// `height` constant) -- the pencil draws along the ruler's actual bottom
/// edge, not through its center, matching how you'd draw against a real
/// ruler.
const double kRulerHalfHeight = 23;

class RulerState extends InstrumentState {
  double lengthCm;

  /// Whether the drawing pencil attached to this ruler is "ready to draw"
  /// (shown blue). Tap the pencil to arm it, then drag it along the ruler's
  /// edge to draw a straight line snapped to that edge.
  bool pencilArmed;

  /// Where the pencil currently sits along the ruler, as a distance (px)
  /// from the edge's start (its left end, at rotation 0). Draggable whether
  /// armed or not, so the pencil icon always shows/follows its real
  /// position instead of staying pinned to a fixed spot.
  double pencilOffsetPx;

  RulerState({
    required super.pivot,
    super.rotation = 0,
    this.lengthCm = 20,
    this.pencilArmed = false,
    double? pencilOffsetPx,
  }) : pencilOffsetPx = pencilOffsetPx ?? (lengthCm * kPxPerCm) / 2;

  double get lengthPx => lengthCm * kPxPerCm;

  /// The edge the attached pencil draws along -- the ruler's top edge,
  /// opposite the side the pencil icon sits on (local y = +34), matching
  /// how you'd hold a pencil against the far edge of a real ruler.
  (Offset, Offset) get drawEdge {
    final halfLen = lengthPx / 2;
    return (
      rotatedLocal(-halfLen, -kRulerHalfHeight),
      rotatedLocal(halfLen, -kRulerHalfHeight),
    );
  }

  @override
  List<(Offset, Offset)> strokeableEdges() => [drawEdge];

  @override
  Map<String, Offset> handleWorldPositions() {
    final halfLen = lengthPx / 2;
    final clampedOffset = pencilOffsetPx.clamp(0.0, lengthPx);
    return {
      'move': rotatedLocal(0, -28),
      'rotate': rotatedLocal(halfLen + 18, 0),
      'remove': rotatedLocal(-halfLen - 18, 0),
      'pencil': rotatedLocal(-halfLen + clampedOffset, 34),
    };
  }
}

class ProtractorState extends InstrumentState {
  double radius; // px
  bool pencilArmed;
  double pencilAngle; // radians, relative to local coordinate system (0 is right, -pi is left)

  ProtractorState({
    required super.pivot,
    super.rotation = 0,
    this.radius = 120,
    this.pencilArmed = false,
    this.pencilAngle = -pi / 4, // starts at 45 degrees to avoid overlapping 'remove' handle
  });

  @override
  List<(Offset, Offset)> strokeableEdges() {
    // The flat (diameter) edge along the bottom of the semicircle.
    return [(rotatedLocal(-radius, 0), rotatedLocal(radius, 0))];
  }

  @override
  Map<String, Offset> handleWorldPositions() {
    return {
      'pencil': rotatedLocal(radius * cos(pencilAngle), radius * sin(pencilAngle)),
      'move': rotatedLocal(0, 26),
      'rotate': rotatedLocal(radius + 18, 0),
      'resize': rotatedLocal(-radius - 18, 0),
    };
  }
}

class CompassState extends InstrumentState {
  double radiusCm;
  double armAngle; // radians, measured from the pivot
  bool locked;
  List<Offset> tracedArcPoints; // live world-space points while dragging

  CompassState({
    required super.pivot,
    super.rotation = 0,
    this.radiusCm = 5,
    this.armAngle = -pi / 4,
    this.locked = false,
    List<Offset>? tracedArcPoints,
  }) : tracedArcPoints = tracedArcPoints ?? [];

  double get radiusPx => radiusCm * kPxPerCm;

  Offset get tipWorldPosition =>
      pivot + Offset(cos(armAngle), sin(armAngle)) * radiusPx;

  /// The hinge/joint point where the two compass legs meet, bulging away
  /// from the pivot-tip line by an amount proportional to the radius, so
  /// the compass visually "opens up" as it's widened -- matching a real
  /// drafting compass rather than a single straight leg.
  Offset get hingePoint {
    final tip = tipWorldPosition;
    final vec = tip - pivot;
    final len = vec.distance;
    if (len < 1) return pivot + const Offset(0, -40);
    final unitPerp = Offset(vec.dy, -vec.dx) / len;
    final bulge = (len * 0.35).clamp(24.0, 90.0);
    return pivot + vec * 0.5 + unitPerp * bulge;
  }

  @override
  Map<String, Offset> handleWorldPositions() {
    return {'pivot': pivot, 'hinge': hingePoint, 'tip': tipWorldPosition};
  }
}

enum SetSquareKind { fortyFive, thirtySixty }

class SetSquareState extends InstrumentState {
  SetSquareKind kind;
  double scale;

  /// Whether the drawing pencil attached to this set square is "ready to
  /// draw" (shown blue). Tap the pencil to arm it, then drag it along any
  /// of the square's three edges to draw a straight line snapped to that
  /// edge.
  bool pencilArmed;

  /// Which edge (0 = v0->v1, 1 = v1->v2, 2 = v2->v0) the pencil currently
  /// rides on. Dragging the pencil near a different edge slides it onto
  /// that edge instead, so all three sides are usable as a straight-edge.
  int pencilEdgeIndex;

  /// Where the pencil sits along its current edge, as a distance (px) from
  /// that edge's first vertex. Draggable whether armed or not, so the
  /// pencil icon always shows/follows its real position instead of staying
  /// pinned to a fixed spot.
  double pencilOffsetPx;

  SetSquareState({
    required super.pivot,
    super.rotation = 0,
    this.kind = SetSquareKind.fortyFive,
    this.scale = 1.0,
    this.pencilArmed = false,
    this.pencilEdgeIndex = 0,
    double? pencilOffsetPx,
  }) : pencilOffsetPx = pencilOffsetPx ?? _baseLegPx / 2;

  static const double _baseLegPx = 220;

  /// Right-angle vertex at the local origin; legs run along +x and +y.
  List<Offset> localVertices() {
    final legLen = _baseLegPx * scale;
    switch (kind) {
      case SetSquareKind.fortyFive:
        return [Offset.zero, Offset(legLen, 0), Offset(0, -legLen)];
      case SetSquareKind.thirtySixty:
        // 60° angle at the origin's base neighbour -> height = legLen*tan(60°)
        final height = legLen * tan(pi / 3);
        return [Offset.zero, Offset(legLen, 0), Offset(0, -height)];
    }
  }

  List<Offset> worldVertices() =>
      localVertices().map((p) => rotatedLocal(p.dx, p.dy)).toList();

  @override
  List<(Offset, Offset)> strokeableEdges() {
    final v = worldVertices();
    return [(v[0], v[1]), (v[1], v[2]), (v[2], v[0])];
  }

  /// The edge (by index: 0 = v0->v1, 1 = v1->v2, 2 = v2->v0) the attached
  /// pencil currently rides on and draws along.
  (Offset, Offset) get drawEdge =>
      strokeableEdges()[pencilEdgeIndex.clamp(0, 2)];

  Offset _outward(Offset vertex, Offset from, double amount) {
    final dir = vertex - from;
    final len = dir.distance == 0 ? 1.0 : dir.distance;
    return vertex + dir / len * amount;
  }

  /// Unit normal for the given edge that points away from the triangle's
  /// interior (i.e. away from the third vertex), so the pencil icon and
  /// tick marks sit just outside the body rather than on top of the fill.
  Offset outwardNormalForEdge(Offset a, Offset b, Offset thirdVertex) {
    final dir = b - a;
    final len = dir.distance;
    if (len == 0) return const Offset(0, -1);
    final unit = dir / len;
    final normal = Offset(-unit.dy, unit.dx);
    final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    final towardThird = thirdVertex - mid;
    final dot = normal.dx * towardThird.dx + normal.dy * towardThird.dy;
    return dot > 0 ? -normal : normal;
  }

  @override
  Map<String, Offset> handleWorldPositions() {
    final verts = worldVertices();
    final centroid = Offset(
      (verts[0].dx + verts[1].dx + verts[2].dx) / 3,
      (verts[0].dy + verts[1].dy + verts[2].dy) / 3,
    );

    final edges = strokeableEdges();
    final idx = pencilEdgeIndex.clamp(0, 2);
    final edge = edges[idx];
    final thirdVertex = verts[(idx + 2) % 3];
    final edgeLen = (edge.$2 - edge.$1).distance;
    final edgeUnit = edgeLen == 0
        ? const Offset(1, 0)
        : (edge.$2 - edge.$1) / edgeLen;
    final clampedOffset = pencilOffsetPx.clamp(0.0, edgeLen);
    final onEdge = edge.$1 + edgeUnit * clampedOffset;
    final outward = outwardNormalForEdge(edge.$1, edge.$2, thirdVertex);

    return {
      'move': centroid,
      'remove': _outward(verts[0], centroid, 20),
      'rotate': _outward(verts[1], centroid, 20),
      'resize': _outward(verts[2], centroid, 20),
      'pencil': onEdge + outward * 20,
    };
  }
}
