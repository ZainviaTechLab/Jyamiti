import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../providers/theme_provider.dart';
import '../instruments/instrument_models.dart';
import '../instruments/ruler_widget.dart';
import '../instruments/protractor_widget.dart';
import '../instruments/compass_widget.dart';
import '../instruments/set_square_widget.dart';

class MathsPadStrokePoint {
  Offset offset;
  MathsPadStrokePoint(this.offset);
}

class MathsPadLine {
  final List<MathsPadStrokePoint> points;
  final Color color;
  final double strokeWidth;
  final bool isEraser;
  final bool isShape;

  // A Fill Tool result: a rasterized flood-fill of some enclosed region,
  // rendered as an image instead of a stroked path. When set, `points` holds
  // exactly 2 entries -- the world-space top-left and bottom-right corners of
  // `fillWorldBounds` -- purely so this line still participates in the
  // generic points-based bounds/culling/move/scale/copy machinery below
  // without any of it needing to know fills exist.
  ui.Image? fillImage;
  Rect? fillWorldBounds;

  Path? cachedPath;
  Rect? cachedBounds;

  MathsPadLine({
    required this.points,
    required this.color,
    required this.strokeWidth,
    this.isEraser = false,
    this.isShape = false,
    this.fillImage,
    this.fillWorldBounds,
    this.cachedPath,
    this.cachedBounds,
  });

  void invalidateCache() {
    cachedPath = null;
    cachedBounds = null;
    // Keep the rendered image's rect in sync after a move/resize drag (both
    // just translate/scale `points` in place). Rotation deliberately isn't
    // synced here -- rotating the two corner points would only ever produce
    // a skewed axis-aligned re-bound, not a real image rotation, so a
    // rotated selection intentionally leaves a filled region's image
    // stationary (see the rotate branch in _onScaleUpdate).
    if (fillImage != null && points.length >= 2) {
      fillWorldBounds = Rect.fromPoints(points[0].offset, points[1].offset);
    }
  }
}

/// A typed text label placed on the canvas (e.g. "A", "5 cm", "∠ABC") --
/// draggable and re-editable, independent of the freehand stroke system.
class MathsPadTextLabel {
  Offset position; // world-space, top-left anchor
  String text;
  Color color;
  double fontSize;

  MathsPadTextLabel({
    required this.position,
    required this.text,
    required this.color,
    this.fontSize = 20,
  });

  Size get measuredSize {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.size;
  }

  Rect get worldBounds => position & measuredSize;
}

enum CanvasToolMode {
  pen,
  straightLine,
  angle,
  polygonAngle,
  circleArc,
  fill,
  text,
  spacer,
  eraser,
  tapSelect,
  lasso,
  pan,
}

enum EraserMode { area, stroke }

enum SelectionHandleType {
  none,
  move,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  rotate,
}

enum CanvasBgMode { grid, ruled, blank, jyamitiCosmos }

enum BasicShapeType {
  circle,
  square,
  rectangle,
  triangle,
  rightTriangle,
  pentagon,
  hexagon,
  diamond,
  star,
  coordinateAxes,
  arrowHorizontal,
  arrowVertical,
  cube3d,
}

class _ShapeToolItem {
  final BasicShapeType type;
  final IconData icon;
  final String tooltip;

  const _ShapeToolItem(this.type, this.icon, this.tooltip);
}

/// A permanent "XX.X°" angle marker left behind by the Angle Tool / Polygon
/// Angle Tool once fixed: an arc between the two rays plus a label placed
/// along their bisector, so both sit visually inside the angle's wedge.
class _FixedAngleLabel {
  // Mutable so the Spacer Tool can shift it along with its source lines
  // when they move.
  Offset vertex;
  final double startAngle; // radians, direction of the first ray
  final double sweepAngle; // signed radians, shortest path to the second ray
  final String text;
  // The two stroke objects that form this angle's rays. If either gets
  // erased/undone/deleted, this label is orphaned and should disappear too.
  final List<MathsPadLine> sourceLines;

  _FixedAngleLabel({
    required this.vertex,
    required this.startAngle,
    required this.sweepAngle,
    required this.text,
    required this.sourceLines,
  });

  static const double labelRadius = 42;

  Offset get labelPosition {
    final bisector = startAngle + sweepAngle / 2;
    return vertex + Offset(cos(bisector), sin(bisector)) * labelRadius;
  }
}

/// Snapshot of everything being pushed apart by one Spacer Tool drag --
/// captured once (with each item's ORIGINAL position) the moment the drag's
/// axis is decided, so the live shift each frame is computed fresh from the
/// original positions rather than compounding small errors by repeatedly
/// nudging an already-nudged position.
class _SpacerDragState {
  final bool isVertical;
  final Offset startWorld;
  final List<MathsPadLine> lines;
  final Map<MathsPadLine, List<Offset>> originalLinePoints;
  final List<MathsPadTextLabel> labels;
  final Map<MathsPadTextLabel, Offset> originalLabelPositions;
  final List<_FixedAngleLabel> angleLabels;
  final Map<_FixedAngleLabel, Offset> originalAngleVertices;

  _SpacerDragState({
    required this.isVertical,
    required this.startWorld,
    required this.lines,
    required this.originalLinePoints,
    required this.labels,
    required this.originalLabelPositions,
    required this.angleLabels,
    required this.originalAngleVertices,
  });
}

/// One pink arc marking an angle from the Angle Tool / Polygon Angle Tool --
/// [live] ones (still being dragged) are drawn lighter than fixed ones.
class _AngleArcSpec {
  final Offset vertex;
  final double startAngle;
  final double sweepAngle;
  final bool live;

  const _AngleArcSpec({
    required this.vertex,
    required this.startAngle,
    required this.sweepAngle,
    required this.live,
  });
}

class _AngleArcPainter extends CustomPainter {
  final List<_AngleArcSpec> arcs;

  _AngleArcPainter(this.arcs);

  static const double _radius = 30;

  @override
  void paint(Canvas canvas, Size size) {
    for (final spec in arcs) {
      final paint = Paint()
        ..color = spec.live
            ? const Color(0xFFEC4899).withOpacity(0.55)
            : const Color(0xFFEC4899)
        ..style = PaintingStyle.stroke
        ..strokeWidth = spec.live ? 2.0 : 2.5
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: spec.vertex, radius: _radius),
        spec.startAngle,
        spec.sweepAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AngleArcPainter oldDelegate) => true;
}

const List<_ShapeToolItem> _shapeTools = [
  _ShapeToolItem(
    BasicShapeType.circle,
    Icons.panorama_fish_eye_rounded,
    'Circle',
  ),
  _ShapeToolItem(BasicShapeType.square, Icons.crop_square_rounded, 'Square'),
  _ShapeToolItem(
    BasicShapeType.rectangle,
    Icons.rectangle_outlined,
    'Rectangle',
  ),
  _ShapeToolItem(
    BasicShapeType.triangle,
    Icons.change_history_rounded,
    'Triangle',
  ),
  _ShapeToolItem(
    BasicShapeType.rightTriangle,
    Icons.details_rounded,
    'Right Triangle',
  ),
  _ShapeToolItem(BasicShapeType.pentagon, Icons.pentagon_outlined, 'Pentagon'),
  _ShapeToolItem(BasicShapeType.hexagon, Icons.hexagon_outlined, 'Hexagon'),
  _ShapeToolItem(
    BasicShapeType.diamond,
    Icons.diamond_outlined,
    'Diamond / Rhombus',
  ),
  _ShapeToolItem(BasicShapeType.star, Icons.star_outline_rounded, 'Star'),
  _ShapeToolItem(
    BasicShapeType.coordinateAxes,
    Icons.add_chart_rounded,
    '2D Coordinate Axes',
  ),
  _ShapeToolItem(
    BasicShapeType.arrowHorizontal,
    Icons.east_rounded,
    'Horizontal Arrow',
  ),
  _ShapeToolItem(
    BasicShapeType.arrowVertical,
    Icons.north_rounded,
    'Vertical Arrow',
  ),
  _ShapeToolItem(
    BasicShapeType.cube3d,
    Icons.view_in_ar_rounded,
    '3D Cube Wireframe',
  ),
];

class MathsPadWidget extends StatefulWidget {
  final VoidCallback? onClose;
  final bool isInline;
  final String? questionText;
  final bool isFullScreen;
  final VoidCallback? onToggleFullScreen;
  final bool isTransparentBg;
  final List<MathsPadLine>? initialLines;
  final bool enableSaveNotes;
  final String? noteId;
  final String? noteTitle;

  const MathsPadWidget({
    super.key,
    this.onClose,
    this.isInline = true,
    this.questionText,
    this.isFullScreen = false,
    this.onToggleFullScreen,
    this.isTransparentBg = false,
    this.initialLines,
    this.enableSaveNotes = false,
    this.noteId,
    this.noteTitle,
  });

  @override
  State<MathsPadWidget> createState() => _MathsPadWidgetState();
}

class _MathsPadWidgetState extends State<MathsPadWidget>
    with SingleTickerProviderStateMixin {
  final List<MathsPadLine> _lines = [];
  final List<MathsPadLine> _undoHistory = [];
  MathsPadLine? _currentLine;

  // Geometry instruments (ruler, protractor, compass, set squares) overlaid
  // on the canvas. See presentation/features/mathpad/instruments/.
  final List<InstrumentState> _instruments = [];
  // The canvas's own visible size (excludes the toolbar above it), kept up
  // to date by the LayoutBuilder in build() -- used to center newly-added
  // instruments in the actually-visible area rather than the whole widget
  // (which would incorrectly include the toolbar's height).
  Size _canvasSize = const Size(800, 600);
  Offset? _snappedEdgeStart;
  Offset? _snappedEdgeVector;

  // Angle Tool: draw a line, then a second line from either of its ends,
  // showing the live angle between them; releasing fixes it permanently.
  Offset? _angleLineAStart;
  Offset? _angleLineAEnd;
  bool _angleWaitingForSecondLine = false;
  Offset? _angleVertex;
  Offset? _angleOtherEndOfA;
  Offset? _angleLiveEnd;
  double? _angleLiveDegrees;
  // The actual line-A stroke object (so a fixed label can be tied back to
  // both strokes that formed it, and cleaned up if either gets erased).
  MathsPadLine? _angleLineAObject;
  final List<_FixedAngleLabel> _fixedAngleLabels = [];

  // Polygon Angle Tool: chains segments end-to-end (each new drag must
  // continue from the last committed vertex), showing/fixing the interior
  // angle at every joint; ending a segment back near the very first vertex
  // closes the polygon and also fixes the closing angle there.
  List<Offset> _polygonVertices = [];
  // Parallel to _polygonVertices: segmentLines[i] connects vertices[i] to
  // vertices[i+1]. Kept so each fixed vertex-angle label can be tied back to
  // the two actual segment strokes that formed it.
  List<MathsPadLine> _polygonSegmentLines = [];
  Offset? _polygonLiveEnd;
  double? _polygonLiveDegrees;
  bool _polygonWillClose = false;

  // Circle/Arc Tool: drag out to set the radius (a straight line, like a
  // compass's first leg), then keep dragging in a curve around the same
  // center -- once you've rotated more than a few degrees away from that
  // initial radius direction, the tool starts tracing an arc at the locked
  // (max-reached) radius instead of a straight line. On release, only the
  // traced arc/circle remains -- the initial straight radius segment is
  // discarded if you never actually rotated.
  Offset? _circleCenter;
  double _circleMaxRadius = 0;
  double? _circleStartAngle;
  bool _circleHasStartedSweeping = false;
  List<Offset> _circleArcPoints = [];
  Offset? _circleLiveEnd;
  // The circle only "arms" (locks its radius and becomes ready to sweep an
  // arc) once the pointer has held still at some length for a full second --
  // any drag that never pauses that long never starts a circle at all.
  Timer? _circleHoldTimer;
  Offset? _circleHoldAnchor;

  // ─── Straight Line Tool ───────────────────────────────────────────────
  // When true, the line snaps to whichever of horizontal/vertical is closer
  // to the actual drag angle instead of following it freely. Toggled by
  // tapping the tool's own toolbar button again while it's already active
  // (same convention as the Eraser's Stroke/Area toggle).
  bool _lineAxisLocked = false;
  Offset? _straightLineLiveEnd;

  // ─── Spacer Tool ──────────────────────────────────────────────────────
  // Drag through a gap to push everything past that point further away,
  // live, opening up blank space to work in -- like "Add Space" in note
  // apps. Axis (vertical vs horizontal) is decided from the first ~8px of
  // actual movement, UNLESS _spacerHorizontalOnly is set (toggled by
  // tapping the tool's own toolbar button again), which always forces
  // horizontal. _spacerDrag stays null until the axis is decided.
  Offset? _spacerPointerStart;
  _SpacerDragState? _spacerDrag;
  double _spacerLiveShift = 0;
  bool _spacerHorizontalOnly = false;

  // ─── Text Label Tool ──────────────────────────────────────────────────
  final List<MathsPadTextLabel> _textLabels = [];

  // Dragging an existing label (always available, independent of the active
  // tool, matching how geometry instruments can always be dragged).
  int? _draggedTextLabelIndex;
  Offset? _textDragPointerStart;
  Offset? _textDragLabelStart;
  bool _textDragMoved = false;

  // The inline text-entry editor -- used both for a brand-new label
  // (_textEditingIndex == null) and for re-editing an existing one.
  bool _textEditorOpen = false;
  int? _textEditingIndex;
  Offset? _textEditorWorldPos;
  TextEditingController? _textEditorController;

  // Question Banner Collapsed/Expanded State
  bool _isQuestionBannerExpanded = true;

  // Eraser Mode: Area (Pixel Brush) vs Stroke (Whole Line Delete on Tap)
  EraserMode _eraserMode = EraserMode.stroke;
  DateTime? _lastEraserClickTime;

  // Drag-to-Draw Interactive Shape Tool State
  BasicShapeType? _activeShapeTool;
  Offset? _shapeDragStartPos;
  Offset? _shapeDragCurrentPos;

  // Selected Lines Transformation State (Move, Resize, Rotate)
  SelectionHandleType _activeHandle = SelectionHandleType.none;
  Offset? _transformStartPos;
  Offset? _transformCenter;
  double _initialScaleDist = 1.0;
  double _initialAngle = 0.0;

  // Butter-Smooth Inertial Gliding Momentum Physics Engine
  AnimationController? _frictionController;
  Animation<Offset>? _frictionAnimation;

  // ── 120 FPS Dual-Layer Repaint Boundaries ──────────────────────────────
  // Layer 1: Finished Strokes & Background (Repaints ONLY when lines list changes)
  // Layer 2: Active Drawing Overlay (Repaints ONLY active line being drawn)
  late final ValueNotifier<Offset> _panNotifier;
  late final ValueNotifier<double> _scaleNotifier;
  late final ValueNotifier<int> _finishedStrokesNotifier;
  late final ValueNotifier<int> _activeDrawingNotifier;

  // Active Pointers tracking for Chrome Web Multi-Touch Panning
  final Map<int, Offset> _activePointers = {};
  Offset? _lastCentroid;

  // Hardware Stylus Side Barrel Button & Eraser Tip Detection
  bool _isStylusBarrelPressed = false;

  // Selected Lines & Move Drag State
  final Set<MathsPadLine> _selectedLines = {};
  bool _isDraggingSelection = false;
  Offset? _lastDragWorldPos;

  // Stroke Clipboard for Copy (Ctrl+C) & Paste (Ctrl+V)
  List<MathsPadLine> _clipboard = [];
  Offset? _lastPointerWorldPos;
  int _consecutivePasteCount = 0;

  // Keyboard FocusNode for Ctrl+C / Ctrl+V shortcuts
  final FocusNode _canvasFocusNode = FocusNode();

  // Lasso Selection Points for Free-Select Area Erase & Move
  List<Offset> _lassoPoints = [];

  // Infinite Canvas Pan & Zoom Transformation State
  Offset _panOffset = Offset.zero;
  double _scale = 1.0;

  // Gesture Tracking State
  Offset _initialFocalPoint = Offset.zero;
  Offset _initialPanOffset = Offset.zero;
  double _initialScale = 1.0;

  CanvasToolMode _toolMode = CanvasToolMode.pen;
  Color _selectedColor = const Color(0xFF6366F1);
  double _penWidth = 3.0;
  double _eraserWidth = 14.0;
  double _selectedWidth = 3.0;
  CanvasBgMode _bgMode = CanvasBgMode.grid;

  final List<Color> _palette = const [
    Color(0xFF6366F1), // Indigo
    Color(0xFFEC4899), // Pink
    Color(0xFF10B981), // Green
    Color(0xFFF59E0B), // Amber
    Color(0xFF3B82F6), // Blue
    Color(0xFFEF4444), // Red
    Colors.white,
    Colors.black,
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialLines != null) {
      _lines.addAll(widget.initialLines!);
      for (final line in _lines) {
        _buildAndCachePath(line);
      }
    }
    if (widget.isTransparentBg) {
      _bgMode = CanvasBgMode.blank;
    }
    _panNotifier = ValueNotifier<Offset>(_panOffset);
    _scaleNotifier = ValueNotifier<double>(_scale);
    _finishedStrokesNotifier = ValueNotifier<int>(0);
    _activeDrawingNotifier = ValueNotifier<int>(0);
    _frictionController = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _circleHoldTimer?.cancel();
    _textEditorController?.dispose();
    _canvasFocusNode.dispose();
    _panNotifier.dispose();
    _scaleNotifier.dispose();
    _finishedStrokesNotifier.dispose();
    _activeDrawingNotifier.dispose();
    _frictionController?.dispose();
    super.dispose();
  }

  // Calculate average centroid of active touch pointers
  Offset _calculateCentroid() {
    if (_activePointers.isEmpty) return Offset.zero;
    double sumX = 0;
    double sumY = 0;
    for (final pos in _activePointers.values) {
      sumX += pos.dx;
      sumY += pos.dy;
    }
    return Offset(sumX / _activePointers.length, sumY / _activePointers.length);
  }

  // Start smooth inertial momentum gliding (fling uses ValueNotifier – no rebuild)
  void _startInertialFling(Offset velocity) {
    if (velocity.distance < 80.0) return;

    _frictionController?.stop();

    final Offset targetDelta = velocity * 0.36;
    final Offset startPan = _panOffset;
    final Offset endPan = _panOffset + targetDelta;

    _frictionController = AnimationController(
      duration: Duration(
        milliseconds: (targetDelta.distance * 1.5).clamp(320, 600).toInt(),
      ),
      vsync: this,
    );

    _frictionAnimation = Tween<Offset>(begin: startPan, end: endPan).animate(
      CurvedAnimation(parent: _frictionController!, curve: Curves.easeOutCubic),
    );

    _frictionAnimation!.addListener(() {
      // Update ONLY the ValueNotifier – zero widget-tree rebuilds during inertia!
      _panOffset = _frictionAnimation!.value;
      _panNotifier.value = _panOffset;
    });

    _frictionController!.forward();
  }

  // Convert Screen/Widget Viewport position to World (Infinite Canvas) position
  Offset _screenToWorld(Offset screenPos) {
    if (widget.isTransparentBg) {
      return screenPos;
    }
    return Offset(
      (screenPos.dx - _panOffset.dx) / _scale,
      (screenPos.dy - _panOffset.dy) / _scale,
    );
  }

  /// Drops any fixed Angle Tool / Polygon Angle Tool label whose ray strokes
  /// include one of [removedLines] -- so erasing, undoing, or deleting a
  /// stroke that formed an angle also removes that angle's arc + label
  /// instead of leaving it stranded on screen.
  void _removeOrphanedAngleLabels(Iterable<MathsPadLine> removedLines) {
    if (_fixedAngleLabels.isEmpty) return;
    final Set<MathsPadLine> removedSet = removedLines.toSet();
    if (removedSet.isEmpty) return;
    _fixedAngleLabels.removeWhere(
      (label) => label.sourceLines.any(removedSet.contains),
    );
  }

  // ─── Straight Line Tool ───────────────────────────────────────────────

  /// The nearest endpoint of any other existing stroke within snapping
  /// tolerance of [worldPos], or null if nothing is close enough. Used so
  /// starting (or ending) a new line right next to an existing line's tip
  /// connects to it exactly instead of leaving a small gap/misalignment.
  Offset? _findNearbyLineEndpoint(Offset worldPos, {MathsPadLine? exclude}) {
    const double tolerance = 20.0;
    Offset? best;
    double bestDist = tolerance;
    for (final line in _lines) {
      if (identical(line, exclude)) continue;
      if (line.fillImage != null || line.points.isEmpty) continue;
      for (final candidate in [
        line.points.first.offset,
        line.points.last.offset,
      ]) {
        final double d = (candidate - worldPos).distance;
        if (d < bestDist) {
          bestDist = d;
          best = candidate;
        }
      }
    }
    return best;
  }

  /// When axis-locked, snaps [end] to whichever of horizontal/vertical
  /// (relative to [start]) is closer to the actual drag direction.
  Offset _applyLineAxisLock(Offset start, Offset end) {
    if (!_lineAxisLocked) return end;
    final double dx = (end.dx - start.dx).abs();
    final double dy = (end.dy - start.dy).abs();
    return dx >= dy ? Offset(end.dx, start.dy) : Offset(start.dx, end.dy);
  }

  void _handleStraightLineToolStart(Offset worldPos) {
    final Offset snapped = _findNearbyLineEndpoint(worldPos) ?? worldPos;
    _currentLine = MathsPadLine(
      points: [MathsPadStrokePoint(snapped)],
      color: _selectedColor,
      strokeWidth: _penWidth,
    );
    _straightLineLiveEnd = snapped;
  }

  void _handleStraightLineToolUpdate(Offset worldPos) {
    if (_currentLine == null) return;
    final Offset start = _currentLine!.points.first.offset;
    // A nearby existing endpoint always wins over the axis lock -- landing
    // exactly on another stroke's tip is more useful than a pure H/V line.
    final Offset end =
        _findNearbyLineEndpoint(worldPos, exclude: _currentLine) ??
        _applyLineAxisLock(start, worldPos);
    _currentLine!.points
      ..clear()
      ..add(MathsPadStrokePoint(start))
      ..add(MathsPadStrokePoint(end));
    _straightLineLiveEnd = end;
    _activeDrawingNotifier.value++;
  }

  void _handleStraightLineToolEnd() {
    if (_currentLine == null) return;
    final Offset start = _currentLine!.points.first.offset;
    final Offset end = _currentLine!.points.last.offset;
    if ((end - start).distance > 2) {
      _currentLine!.invalidateCache();
      _lines.add(_currentLine!);
      _finishedStrokesNotifier.value++;
    }
    _currentLine = null;
    _straightLineLiveEnd = null;
  }

  // ─── Spacer Tool ──────────────────────────────────────────────────────

  void _handleSpacerToolStart(Offset worldPos) {
    _spacerPointerStart = worldPos;
    _spacerDrag = null;
    _spacerLiveShift = 0;
  }

  void _handleSpacerToolUpdate(Offset worldPos) {
    if (_spacerPointerStart == null) return;

    if (_spacerDrag == null) {
      final Offset delta = worldPos - _spacerPointerStart!;
      const double activateThreshold = 8.0;
      if (delta.distance < activateThreshold) return;

      final bool isVertical = _spacerHorizontalOnly
          ? false
          : delta.dy.abs() >= delta.dx.abs();
      final Offset start = _spacerPointerStart!;
      const double tolerance = 2.0;
      final double startCoord = isVertical ? start.dy : start.dx;

      final List<MathsPadLine> affectedLines = _lines.where((line) {
        if (line.points.isEmpty) return false;
        final double minCoord = isVertical
            ? line.points.map((p) => p.offset.dy).reduce(min)
            : line.points.map((p) => p.offset.dx).reduce(min);
        return minCoord >= startCoord - tolerance;
      }).toList();
      final Map<MathsPadLine, List<Offset>> originalLinePoints = {
        for (final line in affectedLines)
          line: line.points.map((p) => p.offset).toList(),
      };

      final List<MathsPadTextLabel> affectedLabels = _textLabels.where((l) {
        final double coord = isVertical ? l.position.dy : l.position.dx;
        return coord >= startCoord - tolerance;
      }).toList();
      final Map<MathsPadTextLabel, Offset> originalLabelPositions = {
        for (final l in affectedLabels) l: l.position,
      };

      final Set<MathsPadLine> affectedLineSet = affectedLines.toSet();
      final List<_FixedAngleLabel> affectedAngleLabels = _fixedAngleLabels
          .where((l) => l.sourceLines.any(affectedLineSet.contains))
          .toList();
      final Map<_FixedAngleLabel, Offset> originalAngleVertices = {
        for (final l in affectedAngleLabels) l: l.vertex,
      };

      _spacerDrag = _SpacerDragState(
        isVertical: isVertical,
        startWorld: start,
        lines: affectedLines,
        originalLinePoints: originalLinePoints,
        labels: affectedLabels,
        originalLabelPositions: originalLabelPositions,
        angleLabels: affectedAngleLabels,
        originalAngleVertices: originalAngleVertices,
      );
    }

    final _SpacerDragState drag = _spacerDrag!;
    final double rawShift = drag.isVertical
        ? worldPos.dy - drag.startWorld.dy
        : worldPos.dx - drag.startWorld.dx;
    // Only ever pushes content further away -- dragging back toward the
    // start just closes the gap back down to nothing, never past it.
    final double shift = rawShift.clamp(0.0, double.infinity);
    _spacerLiveShift = shift;
    final Offset shiftOffset = drag.isVertical
        ? Offset(0, shift)
        : Offset(shift, 0);

    for (final line in drag.lines) {
      final List<Offset> original = drag.originalLinePoints[line]!;
      for (int i = 0; i < line.points.length; i++) {
        line.points[i].offset = original[i] + shiftOffset;
      }
      line.invalidateCache();
    }
    for (final label in drag.labels) {
      label.position = drag.originalLabelPositions[label]! + shiftOffset;
    }
    for (final angleLabel in drag.angleLabels) {
      angleLabel.vertex =
          drag.originalAngleVertices[angleLabel]! + shiftOffset;
    }
    _finishedStrokesNotifier.value++;
  }

  void _handleSpacerToolEnd() {
    _spacerPointerStart = null;
    _spacerDrag = null;
    _spacerLiveShift = 0;
  }

  // ─── Angle Tool ──────────────────────────────────────────────────────────

  double _angleBetween(Offset vecA, Offset vecB) {
    double diff = (vecB.direction - vecA.direction).abs();
    if (diff > pi) diff = 2 * pi - diff;
    return diff * 180 / pi;
  }

  /// Signed shortest angular path from [a1] to [a2] (radians, in (-pi, pi]),
  /// used to draw the pink angle arc sweeping the correct direction and to
  /// place the label along the bisector, on the inside of the wedge.
  double _signedAngleDiff(double a1, double a2) {
    double diff = a2 - a1;
    while (diff > pi) {
      diff -= 2 * pi;
    }
    while (diff < -pi) {
      diff += 2 * pi;
    }
    return diff;
  }

  void _resetAngleTool() {
    _angleLineAStart = null;
    _angleLineAEnd = null;
    _angleWaitingForSecondLine = false;
    _angleLineAObject = null;
    _angleVertex = null;
    _angleOtherEndOfA = null;
    _angleLiveEnd = null;
    _angleLiveDegrees = null;
  }

  void _handleAngleToolStart(Offset worldPos) {
    const double vertexTolerance = 30.0;

    if (_angleWaitingForSecondLine) {
      final nearStart = _angleLineAStart != null &&
          (worldPos - _angleLineAStart!).distance <= vertexTolerance;
      final nearEnd = _angleLineAEnd != null &&
          (worldPos - _angleLineAEnd!).distance <= vertexTolerance;
      if (nearStart || nearEnd) {
        _angleVertex = nearStart ? _angleLineAStart : _angleLineAEnd;
        _angleOtherEndOfA = nearStart ? _angleLineAEnd : _angleLineAStart;
        _currentLine = MathsPadLine(
          points: [MathsPadStrokePoint(_angleVertex!)],
          color: _selectedColor,
          strokeWidth: _penWidth,
        );
        return;
      }
      // Not near either end of line A -- start a brand new angle construction.
      _resetAngleTool();
    }

    _angleLineAStart = worldPos;
    _currentLine = MathsPadLine(
      points: [MathsPadStrokePoint(worldPos)],
      color: _selectedColor,
      strokeWidth: _penWidth,
    );
  }

  void _handleAngleToolUpdate(Offset worldPos) {
    if (_currentLine == null) return;
    final start = _currentLine!.points.first.offset;
    _currentLine!.points
      ..clear()
      ..add(MathsPadStrokePoint(start))
      ..add(MathsPadStrokePoint(worldPos));

    if (_angleWaitingForSecondLine &&
        _angleVertex != null &&
        _angleOtherEndOfA != null) {
      _angleLiveEnd = worldPos;
      _angleLiveDegrees = _angleBetween(
        _angleOtherEndOfA! - _angleVertex!,
        worldPos - _angleVertex!,
      );
    }
    _activeDrawingNotifier.value++;
  }

  void _handleAngleToolEnd() {
    if (_currentLine == null) return;
    _currentLine!.invalidateCache();
    _lines.add(_currentLine!);
    _finishedStrokesNotifier.value++;

    if (!_angleWaitingForSecondLine) {
      // Line A just finished -- now wait for line B from one of its ends.
      _angleLineAEnd = _currentLine!.points.last.offset;
      _angleLineAObject = _currentLine!;
      _angleWaitingForSecondLine = true;
    } else {
      // Line B just finished -- fix the angle as a permanent arc + label.
      if (_angleLiveDegrees != null &&
          _angleVertex != null &&
          _angleOtherEndOfA != null &&
          _angleLineAObject != null) {
        final vertex = _angleVertex!;
        final a1 = (_angleOtherEndOfA! - vertex).direction;
        final a2 = (_currentLine!.points.last.offset - vertex).direction;
        _fixedAngleLabels.add(
          _FixedAngleLabel(
            vertex: vertex,
            startAngle: a1,
            sweepAngle: _signedAngleDiff(a1, a2),
            text: '${_angleLiveDegrees!.toStringAsFixed(1)}°',
            sourceLines: [_angleLineAObject!, _currentLine!],
          ),
        );
      }
      _resetAngleTool();
    }
    _currentLine = null;
  }

  // ─── Polygon Angle Tool ──────────────────────────────────────────────────

  void _resetPolygonTool() {
    _polygonVertices = [];
    _polygonSegmentLines = [];
    _polygonLiveEnd = null;
    _polygonLiveDegrees = null;
    _polygonWillClose = false;
  }

  void _handlePolygonToolStart(Offset worldPos) {
    const double vertexTolerance = 30.0;

    if (_polygonVertices.isNotEmpty) {
      final last = _polygonVertices.last;
      if ((worldPos - last).distance > vertexTolerance) {
        // Not continuing from the last vertex -- start a brand new polygon.
        _resetPolygonTool();
      }
    }

    final segmentStart = _polygonVertices.isEmpty
        ? worldPos
        : _polygonVertices.last;
    if (_polygonVertices.isEmpty) {
      _polygonVertices = [worldPos];
    }

    _currentLine = MathsPadLine(
      points: [MathsPadStrokePoint(segmentStart)],
      color: _selectedColor,
      strokeWidth: _penWidth,
    );
    _polygonWillClose = false;
  }

  void _handlePolygonToolUpdate(Offset worldPos) {
    if (_currentLine == null) return;
    const double closeTolerance = 26.0;

    Offset endPoint = worldPos;
    _polygonWillClose = false;
    if (_polygonVertices.length >= 3) {
      final firstPt = _polygonVertices.first;
      if ((worldPos - firstPt).distance <= closeTolerance) {
        endPoint = firstPt;
        _polygonWillClose = true;
      }
    }

    final start = _currentLine!.points.first.offset;
    _currentLine!.points
      ..clear()
      ..add(MathsPadStrokePoint(start))
      ..add(MathsPadStrokePoint(endPoint));

    if (_polygonVertices.length >= 2) {
      final vertex = _polygonVertices.last;
      final prevVertex = _polygonVertices[_polygonVertices.length - 2];
      _polygonLiveEnd = endPoint;
      _polygonLiveDegrees = _angleBetween(prevVertex - vertex, endPoint - vertex);
    }
    _activeDrawingNotifier.value++;
  }

  void _handlePolygonToolEnd() {
    if (_currentLine == null) return;
    _currentLine!.invalidateCache();
    _lines.add(_currentLine!);
    _finishedStrokesNotifier.value++;

    final segmentStart = _currentLine!.points.first.offset;
    final segmentEnd = _currentLine!.points.last.offset;

    if (_polygonVertices.length >= 2 &&
        _polygonLiveDegrees != null &&
        _polygonSegmentLines.isNotEmpty) {
      final vertex = segmentStart;
      final prevVertex = _polygonVertices[_polygonVertices.length - 2];
      final a1 = (prevVertex - vertex).direction;
      final a2 = (segmentEnd - vertex).direction;
      _fixedAngleLabels.add(
        _FixedAngleLabel(
          vertex: vertex,
          startAngle: a1,
          sweepAngle: _signedAngleDiff(a1, a2),
          text: '${_polygonLiveDegrees!.toStringAsFixed(1)}°',
          sourceLines: [_polygonSegmentLines.last, _currentLine!],
        ),
      );
    }

    if (_polygonWillClose) {
      // Closing segment: also fix the angle at the very first vertex,
      // between the closing edge coming in and the polygon's first edge.
      final p0 = _polygonVertices.first;
      final p1 = _polygonVertices[1];
      final a1 = (segmentStart - p0).direction;
      final a2 = (p1 - p0).direction;
      final closingDeg = _angleBetween(segmentStart - p0, p1 - p0);
      if (_polygonSegmentLines.isNotEmpty) {
        _fixedAngleLabels.add(
          _FixedAngleLabel(
            vertex: p0,
            startAngle: a1,
            sweepAngle: _signedAngleDiff(a1, a2),
            text: '${closingDeg.toStringAsFixed(1)}°',
            sourceLines: [_polygonSegmentLines.first, _currentLine!],
          ),
        );
      }
      _resetPolygonTool();
    } else {
      _polygonVertices.add(segmentEnd);
      _polygonSegmentLines.add(_currentLine!);
      _polygonLiveEnd = null;
      _polygonLiveDegrees = null;
    }
    _currentLine = null;
  }

  // ─── Circle/Arc Tool ─────────────────────────────────────────────────────

  void _resetCircleArcTool() {
    _circleHoldTimer?.cancel();
    _circleHoldTimer = null;
    _circleHoldAnchor = null;
    _circleCenter = null;
    _circleMaxRadius = 0;
    _circleStartAngle = null;
    _circleHasStartedSweeping = false;
    _circleArcPoints = [];
    _circleLiveEnd = null;
  }

  void _handleCircleArcToolStart(Offset worldPos) {
    _circleHoldTimer?.cancel();
    _circleHoldTimer = null;
    _circleHoldAnchor = null;
    _circleCenter = worldPos;
    _circleMaxRadius = 0;
    _circleStartAngle = null;
    _circleHasStartedSweeping = false;
    _circleArcPoints = [];
    _circleLiveEnd = null;
    _currentLine = MathsPadLine(
      points: [MathsPadStrokePoint(worldPos)],
      color: _selectedColor,
      strokeWidth: _penWidth,
    );
  }

  /// Fires once the pointer has held still at [holdPos] for a full second --
  /// arms the tool to start sweeping an arc at that locked radius. If the
  /// pointer moves again before this fires, [_handleCircleArcToolUpdate]
  /// cancels it and starts a fresh one, so a circle only ever begins if the
  /// user actually pauses; a continuous drag that never pauses draws nothing.
  void _armCircleArcHold(Offset holdPos) {
    if (!mounted || _currentLine == null || _circleCenter == null) return;
    setState(() {
      _circleHasStartedSweeping = true;
      _circleStartAngle = (holdPos - _circleCenter!).direction;
      _circleMaxRadius = (holdPos - _circleCenter!).distance;
      _circleLiveEnd = null;
      _circleArcPoints = [
        _circleCenter! +
            Offset(cos(_circleStartAngle!), sin(_circleStartAngle!)) *
                _circleMaxRadius,
      ];
    });
  }

  void _handleCircleArcToolUpdate(Offset worldPos) {
    if (_currentLine == null || _circleCenter == null) return;
    final vec = worldPos - _circleCenter!;
    final dist = vec.distance;
    if (dist < 1) return;
    final angle = vec.direction;

    if (!_circleHasStartedSweeping) {
      // Still drawing the initial straight radius -- track the live end so
      // the dynamic length badge always matches exactly what's on screen.
      _circleLiveEnd = worldPos;

      // Restart the 1-second hold timer whenever the pointer moves away from
      // wherever it's currently anchored. The timer only ever completes if
      // the pointer stays within a small tolerance of one spot for the full
      // second, which is exactly what "hold a specific length" means here.
      const double holdTolerance = 6.0;
      if (_circleHoldAnchor == null ||
          (worldPos - _circleHoldAnchor!).distance > holdTolerance) {
        _circleHoldAnchor = worldPos;
        _circleHoldTimer?.cancel();
        final Offset anchorForThisHold = worldPos;
        _circleHoldTimer = Timer(
          const Duration(seconds: 1),
          () => _armCircleArcHold(anchorForThisHold),
        );
      }
    }

    if (_circleHasStartedSweeping) {
      final tracedPoint =
          _circleCenter! + Offset(cos(angle), sin(angle)) * _circleMaxRadius;
      if (_circleArcPoints.isEmpty ||
          (tracedPoint - _circleArcPoints.last).distance >= 1.2) {
        _circleArcPoints.add(tracedPoint);
      }
      _currentLine!.points
        ..clear()
        ..addAll(_circleArcPoints.map((p) => MathsPadStrokePoint(p)));
    } else {
      // Still just the initial straight radius preview.
      _currentLine!.points
        ..clear()
        ..add(MathsPadStrokePoint(_circleCenter!))
        ..add(MathsPadStrokePoint(worldPos));
    }
    _activeDrawingNotifier.value++;
  }

  void _handleCircleArcToolEnd() {
    if (_currentLine == null) {
      _resetCircleArcTool();
      return;
    }
    if (_circleHasStartedSweeping && _circleArcPoints.length > 1) {
      _currentLine!.points
        ..clear()
        ..addAll(_circleArcPoints.map((p) => MathsPadStrokePoint(p)));
      _currentLine!.invalidateCache();
      _lines.add(_currentLine!);
      _finishedStrokesNotifier.value++;
    }
    // If the user never actually rotated, there's no arc to keep -- the
    // straight radius preview is discarded (nothing committed).
    _currentLine = null;
    _resetCircleArcTool();
  }

  // ─── Fill Tool (MS Paint-style bucket fill) ──────────────────────────────

  static const int _fillColorTolerance = 40;

  /// Tap-triggered flood fill: rasterizes the current strokes at screen
  /// resolution, floods a contiguous same-color region from [screenTapPos]
  /// (tolerant of anti-aliased edges), and adds the result as a normal
  /// `MathsPadLine` with an image instead of a stroked path -- so undo/redo/
  /// clear, which only ever touch `_lines`/`_undoHistory`, need no changes at
  /// all to support it.
  Future<void> _performBucketFill(Offset screenTapPos) async {
    if (_canvasSize.isEmpty) return;
    final int width = _canvasSize.width.ceil();
    final int height = _canvasSize.height.ceil();
    if (width <= 0 || height <= 0) return;

    final int startX = screenTapPos.dx.floor();
    final int startY = screenTapPos.dy.floor();
    if (startX < 0 || startX >= width || startY < 0 || startY >= height) {
      return;
    }

    // Rasterize just the strokes (not the grid/ruled background pattern --
    // that would risk faint grid lines being misread as fill boundaries) at
    // the exact same pan/scale transform the live painter uses, so the
    // tapped screen pixel lines up with what's actually on screen.
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas offscreenCanvas = Canvas(recorder);
    offscreenCanvas.save();
    offscreenCanvas.translate(_panOffset.dx, _panOffset.dy);
    offscreenCanvas.scale(_scale);
    final _MathsPadFinishedStrokesPainter tempPainter =
        _MathsPadFinishedStrokesPainter(
          lines: _lines,
          bgMode: _bgMode,
          isDark: false,
          canvasBgColor: Colors.transparent,
          panOffset: _panOffset,
          scale: _scale,
        );
    tempPainter._drawStrokes(offscreenCanvas, _lines);
    offscreenCanvas.restore();
    final ui.Picture picture = recorder.endRecording();
    final ui.Image rasterImage = await picture.toImage(width, height);
    final ByteData? byteData = await rasterImage.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    rasterImage.dispose();
    if (byteData == null) return;
    final Uint8List pixels = byteData.buffer.asUint8List();

    int idx(int x, int y) => (y * width + x) * 4;

    final int startIdx = idx(startX, startY);
    final int targetR = pixels[startIdx];
    final int targetG = pixels[startIdx + 1];
    final int targetB = pixels[startIdx + 2];
    final int targetA = pixels[startIdx + 3];

    final int fillR = (_selectedColor.r * 255.0).round().clamp(0, 255);
    final int fillG = (_selectedColor.g * 255.0).round().clamp(0, 255);
    final int fillB = (_selectedColor.b * 255.0).round().clamp(0, 255);
    const int fillA = 255;

    bool closeEnoughToFillColor() {
      return (targetR - fillR).abs() <= _fillColorTolerance &&
          (targetG - fillG).abs() <= _fillColorTolerance &&
          (targetB - fillB).abs() <= _fillColorTolerance &&
          (targetA - fillA).abs() <= _fillColorTolerance;
    }

    // Nothing would actually change -- tapping an area already filled with
    // (close enough to) the current color.
    if (closeEnoughToFillColor()) return;

    bool matchesTarget(int x, int y) {
      final int i = idx(x, y);
      return (pixels[i] - targetR).abs() <= _fillColorTolerance &&
          (pixels[i + 1] - targetG).abs() <= _fillColorTolerance &&
          (pixels[i + 2] - targetB).abs() <= _fillColorTolerance &&
          (pixels[i + 3] - targetA).abs() <= _fillColorTolerance;
    }

    // Scanline span flood fill -- much faster than a naive per-pixel
    // 4-directional flood fill, since a whole contiguous horizontal run of
    // matching pixels is claimed and enqueued in one step instead of one
    // pixel at a time.
    final Uint8List visited = Uint8List(width * height);
    final List<int> stack = <int>[startY * width + startX];
    int minX = startX, maxX = startX, minY = startY, maxY = startY;

    while (stack.isNotEmpty) {
      final int packed = stack.removeLast();
      final int y = packed ~/ width;
      final int x = packed % width;
      if (visited[y * width + x] != 0) continue;
      if (!matchesTarget(x, y)) continue;

      // Expand left to find the start of this span.
      int spanStart = x;
      while (spanStart - 1 >= 0 &&
          visited[y * width + (spanStart - 1)] == 0 &&
          matchesTarget(spanStart - 1, y)) {
        spanStart--;
      }
      // Expand right to find the end of this span.
      int spanEnd = x;
      while (spanEnd + 1 < width &&
          visited[y * width + (spanEnd + 1)] == 0 &&
          matchesTarget(spanEnd + 1, y)) {
        spanEnd++;
      }

      bool aboveAdded = false;
      bool belowAdded = false;
      for (int sx = spanStart; sx <= spanEnd; sx++) {
        visited[y * width + sx] = 1;
        final int px = idx(sx, y);
        pixels[px] = fillR;
        pixels[px + 1] = fillG;
        pixels[px + 2] = fillB;
        pixels[px + 3] = fillA;

        if (sx < minX) minX = sx;
        if (sx > maxX) maxX = sx;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;

        if (y > 0) {
          final bool match = visited[(y - 1) * width + sx] == 0 &&
              matchesTarget(sx, y - 1);
          if (match && !aboveAdded) {
            stack.add((y - 1) * width + sx);
            aboveAdded = true;
          } else if (!match) {
            aboveAdded = false;
          }
        }
        if (y < height - 1) {
          final bool match = visited[(y + 1) * width + sx] == 0 &&
              matchesTarget(sx, y + 1);
          if (match && !belowAdded) {
            stack.add((y + 1) * width + sx);
            belowAdded = true;
          } else if (!match) {
            belowAdded = false;
          }
        }
      }
    }

    if (maxX < minX || maxY < minY) return; // nothing was actually filled

    final int cropW = maxX - minX + 1;
    final int cropH = maxY - minY + 1;
    final Uint8List cropped = Uint8List(cropW * cropH * 4);
    for (int y = 0; y < cropH; y++) {
      for (int x = 0; x < cropW; x++) {
        final int srcX = minX + x;
        final int srcY = minY + y;
        final int dstI = (y * cropW + x) * 4;
        if (visited[srcY * width + srcX] != 0) {
          cropped[dstI] = fillR;
          cropped[dstI + 1] = fillG;
          cropped[dstI + 2] = fillB;
          cropped[dstI + 3] = fillA;
        }
        // else leave as fully transparent (Uint8List defaults to 0)
      }
    }

    final Completer<ui.Image> completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(cropped, cropW, cropH, ui.PixelFormat.rgba8888, (
      ui.Image img,
    ) {
      completer.complete(img);
    });
    final ui.Image fillImage = await completer.future;

    if (!mounted) {
      fillImage.dispose();
      return;
    }

    final Offset worldTopLeft = _screenToWorld(
      Offset(minX.toDouble(), minY.toDouble()),
    );
    final Offset worldBottomRight = _screenToWorld(
      Offset((maxX + 1).toDouble(), (maxY + 1).toDouble()),
    );
    final Rect worldBounds = Rect.fromPoints(worldTopLeft, worldBottomRight);

    final MathsPadLine fillLine = MathsPadLine(
      points: [
        MathsPadStrokePoint(worldBounds.topLeft),
        MathsPadStrokePoint(worldBounds.bottomRight),
      ],
      color: _selectedColor,
      strokeWidth: 0,
      fillImage: fillImage,
      fillWorldBounds: worldBounds,
    );

    setState(() {
      _lines.add(fillLine);
    });
    _finishedStrokesNotifier.value++;
  }

  // ─── Geometry Instruments: helpers ──────────────────────────────────────

  Offset _projectPointOntoSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq == 0) return a;
    final t = (((p - a).dx * ab.dx) + ((p - a).dy * ab.dy)) / lenSq;
    final tc = t.clamp(0.0, 1.0);
    return a + ab * tc;
  }

  Offset _projectPointOntoInfiniteLine(Offset p, Offset origin, Offset dir) {
    final lenSq = dir.dx * dir.dx + dir.dy * dir.dy;
    if (lenSq == 0) return origin;
    final t = (((p - origin).dx * dir.dx) + ((p - origin).dy * dir.dy)) / lenSq;
    return origin + dir * t;
  }

  /// Adds a new instrument, or -- if one matching [isSameTool] already
  /// exists -- just re-centers that existing one instead of piling up a
  /// duplicate. Only one of each tool (Ruler, Protractor, Compass, and each
  /// Set Square kind) is allowed on the canvas at a time.
  void _addInstrument(
    bool Function(InstrumentState) isSameTool,
    InstrumentState Function(Offset center) build,
  ) {
    // Use the canvas's own tracked size (excludes the toolbar above it) --
    // `context.size` here would be the whole widget's size, which used to
    // place new instruments too high/left of the actually-visible canvas.
    final viewportCenter = _screenToWorld(
      Offset(_canvasSize.width / 2, _canvasSize.height / 2),
    );
    setState(() {
      final existingIndex = _instruments.indexWhere(isSameTool);
      if (existingIndex != -1) {
        _instruments[existingIndex].pivot = viewportCenter;
      } else {
        _instruments.add(build(viewportCenter));
      }
    });
  }

  void _commitCompassArc(List<Offset> worldPoints) {
    if (worldPoints.length < 2) return;
    final arcLine = MathsPadLine(
      points: worldPoints.map((p) => MathsPadStrokePoint(p)).toList(),
      color: _selectedColor,
      strokeWidth: _penWidth,
    );
    arcLine.invalidateCache();
    _undoHistory.clear();
    _lines.add(arcLine);
    _finishedStrokesNotifier.value++;
  }

  /// A placed text label: the text itself is IgnorePointer'd (dragging is
  /// handled centrally through the canvas's own gesture detector, same as
  /// every instrument, to avoid the nested-Positioned coordinate bug that
  /// affected per-widget drag handling elsewhere in this file); only the
  /// small remove button is a local tap target.
  Widget _buildTextLabelWidget(int index, MathsPadTextLabel label) {
    return Positioned(
      left: label.position.dx,
      top: label.position.dy,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IgnorePointer(
            child: Text(
              label.text,
              style: TextStyle(
                color: label.color,
                fontSize: label.fontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Positioned(
            right: -10,
            top: -10,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _deleteTextLabel(index),
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 12,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Inline editor shown while placing a new label or re-editing an
  /// existing one -- a small floating card with a text field, matching the
  /// visual style of the other instrument badges in this file.
  Widget _buildTextEditorOverlay(bool isDark) {
    if (!_textEditorOpen ||
        _textEditorWorldPos == null ||
        _textEditorController == null) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: _textEditorWorldPos!.dx,
      top: _textEditorWorldPos!.dy - 26,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF6366F1), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _textEditorController,
                  autofocus: true,
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                    fontSize: 15,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Label text…',
                  ),
                  onSubmitted: (_) => _commitTextEditor(),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _commitTextEditor,
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF22C55E),
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInstrumentWidget(InstrumentState inst) {
    final isDark = context.isDark;
    if (inst is RulerState) {
      return RulerWidget(
        key: ValueKey(inst),
        state: inst,
        isDark: isDark,
        onRemove: () => setState(() => _instruments.remove(inst)),
      );
    } else if (inst is ProtractorState) {
      return ProtractorWidget(
        key: ValueKey(inst),
        state: inst,
        isDark: isDark,
        onRemove: () => setState(() => _instruments.remove(inst)),
      );
    } else if (inst is SetSquareState) {
      return SetSquareWidget(
        key: ValueKey(inst),
        state: inst,
        isDark: isDark,
        onRemove: () => setState(() => _instruments.remove(inst)),
      );
    } else if (inst is CompassState) {
      return CompassWidget(
        key: ValueKey(inst),
        state: inst,
        isDark: isDark,
        onToggleLock: () => setState(() => inst.locked = !inst.locked),
        onRefresh: () => setState(() {
          inst.armAngle = -pi / 4;
          inst.tracedArcPoints = [];
        }),
        onRemove: () => setState(() => _instruments.remove(inst)),
      );
    }
    return const SizedBox.shrink();
  }

  /// Small pill label used by the Angle Tool / Polygon Angle Tool, centered
  /// on [worldPos] (the angle's bisector point, i.e. inside the wedge):
  /// blue while the second line is still being dragged (live), solid dark
  /// once fixed permanently.
  Widget _buildAngleBadge(Offset worldPos, String text, {required bool live}) {
    return Positioned(
      left: worldPos.dx,
      top: worldPos.dy,
      child: IgnorePointer(
        child: FractionalTranslation(
          translation: const Offset(-0.5, -0.5),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              // Fixed labels use a light, translucent background (instead of
              // solid black) so they read as a soft overlay rather than an
              // opaque tag sitting on top of the drawing.
              color: live
                  ? const Color(0xFF2563EB)
                  : Colors.white.withOpacity(0.78),
              borderRadius: BorderRadius.circular(14),
              border: live
                  ? null
                  : Border.all(color: const Color(0xFF1E293B).withOpacity(0.12)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              text,
              style: TextStyle(
                color: live ? Colors.white : const Color(0xFF1E293B),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// World position along the bisector of an angle at [vertex] between ray
  /// [startAngle] and the ray reached by sweeping [sweepAngle] further --
  /// i.e. a point inside the wedge, matching [_FixedAngleLabel.labelPosition].
  Offset _bisectorPoint(Offset vertex, double startAngle, double sweepAngle) {
    final bisector = startAngle + sweepAngle / 2;
    return vertex +
        Offset(cos(bisector), sin(bisector)) * _FixedAngleLabel.labelRadius;
  }

  /// Point just off the midpoint of segment [a]-[b], offset perpendicular by
  /// [offset] px, used to float the Circle/Arc tool's live length badge
  /// beside the radius line instead of directly on top of it.
  Offset _perpendicularMidpoint(Offset a, Offset b, double offset) {
    final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    final dir = b - a;
    if (dir.distance == 0) return mid;
    final normal = Offset(-dir.dy, dir.dx) / dir.distance;
    return mid + normal * offset;
  }

  /// All angle arcs to paint this frame: every fixed one, plus the live one
  /// currently being dragged (if any) for whichever angle tool is active.
  List<_AngleArcSpec> _currentAngleArcs() {
    final arcs = _fixedAngleLabels
        .map(
          (l) => _AngleArcSpec(
            vertex: l.vertex,
            startAngle: l.startAngle,
            sweepAngle: l.sweepAngle,
            live: false,
          ),
        )
        .toList();

    if (_toolMode == CanvasToolMode.angle &&
        _angleWaitingForSecondLine &&
        _angleVertex != null &&
        _angleOtherEndOfA != null &&
        _angleLiveEnd != null) {
      final a1 = (_angleOtherEndOfA! - _angleVertex!).direction;
      final a2 = (_angleLiveEnd! - _angleVertex!).direction;
      arcs.add(
        _AngleArcSpec(
          vertex: _angleVertex!,
          startAngle: a1,
          sweepAngle: _signedAngleDiff(a1, a2),
          live: true,
        ),
      );
    }

    if (_toolMode == CanvasToolMode.polygonAngle &&
        _polygonVertices.length >= 2 &&
        _polygonLiveEnd != null) {
      final vertex = _polygonVertices.last;
      final prevVertex = _polygonVertices[_polygonVertices.length - 2];
      final a1 = (prevVertex - vertex).direction;
      final a2 = (_polygonLiveEnd! - vertex).direction;
      arcs.add(
        _AngleArcSpec(
          vertex: vertex,
          startAngle: a1,
          sweepAngle: _signedAngleDiff(a1, a2),
          live: true,
        ),
      );
    }

    return arcs;
  }

  // ─── Instrument handle drag: centralized hit-testing & updates ─────────
  //
  // Each instrument widget is purely visual for its move/rotate/resize (and
  // the compass's pivot/hinge/tip) handles -- those handles live at
  // shifting `Positioned` offsets inside the pan/zoom-transformed overlay,
  // so a GestureDetector attached directly to one of them would report
  // `localPosition` relative to its OWN small render box, not the canvas's
  // world coordinates. Instead, all of that dragging is funneled through
  // the canvas's single top-level gesture detector below, which already
  // has a correct screen->world conversion via `_screenToWorld`.

  InstrumentState? _draggedInstrument;
  String? _draggedHandle;
  Offset? _instrumentDragStartWorld;
  Offset? _instrumentDragStartPivot;
  double? _instrumentDragStartRotation;
  double? _instrumentDragStartRadiusOrScale;
  Offset? _lastCompassTracePoint;
  bool _pencilDragMoved = false;

  /// Ruler/Set Square straight-edge for the pencil attached to them. For a
  /// Set Square, the pencil isn't fixed to one edge -- this snaps it onto
  /// whichever of the three edges is currently closest to [worldPos], so
  /// dragging around the triangle's perimeter slides it from side to side.
  (Offset, Offset)? _resolvePencilEdge(InstrumentState inst, Offset worldPos) {
    if (inst is RulerState) return inst.drawEdge;
    if (inst is SetSquareState) {
      final edges = inst.strokeableEdges();
      int bestIdx = inst.pencilEdgeIndex.clamp(0, 2);
      double bestDist = double.infinity;
      for (int i = 0; i < edges.length; i++) {
        final proj = _projectPointOntoSegment(worldPos, edges[i].$1, edges[i].$2);
        final d = (proj - worldPos).distance;
        if (d < bestDist) {
          bestDist = d;
          bestIdx = i;
        }
      }
      inst.pencilEdgeIndex = bestIdx;
      return edges[bestIdx];
    }
    return null;
  }

  bool _isPencilArmed(InstrumentState inst) {
    if (inst is RulerState) return inst.pencilArmed;
    if (inst is SetSquareState) return inst.pencilArmed;
    return false;
  }

  void _togglePencilArmed(InstrumentState inst) {
    if (inst is RulerState) inst.pencilArmed = !inst.pencilArmed;
    if (inst is SetSquareState) inst.pencilArmed = !inst.pencilArmed;
  }

  (InstrumentState, String)? _hitTestInstrumentHandles(Offset worldPos) {
    const double tolerance = 26.0;
    for (final inst in _instruments.reversed) {
      for (final entry in inst.handleWorldPositions().entries) {
        if ((entry.value - worldPos).distance <= tolerance) {
          return (inst, entry.key);
        }
      }
      // The compass's pivot dot alone is a small target; grabbing anywhere
      // along its solid pivot leg (pivot -> hinge) also moves the whole
      // compass, matching how you'd actually pick one up.
      if (inst is CompassState) {
        final onLeg = _projectPointOntoSegment(worldPos, inst.pivot, inst.hingePoint);
        if ((onLeg - worldPos).distance <= tolerance) {
          return (inst, 'pivot');
        }
      }
    }
    return null;
  }

  // ─── Text Label Tool ──────────────────────────────────────────────────

  int? _hitTestTextLabel(Offset worldPos) {
    for (int i = _textLabels.length - 1; i >= 0; i--) {
      if (_textLabels[i].worldBounds.inflate(8).contains(worldPos)) return i;
    }
    return null;
  }

  /// Existing labels are always draggable, regardless of the active tool --
  /// matching how geometry instruments always take priority too.
  bool _tryStartTextLabelDrag(Offset worldPos) {
    final int? idx = _hitTestTextLabel(worldPos);
    if (idx == null) return false;
    _draggedTextLabelIndex = idx;
    _textDragPointerStart = worldPos;
    _textDragLabelStart = _textLabels[idx].position;
    _textDragMoved = false;
    return true;
  }

  void _updateTextLabelDrag(Offset worldPos) {
    if (_draggedTextLabelIndex == null ||
        _textDragPointerStart == null ||
        _textDragLabelStart == null) {
      return;
    }
    final Offset delta = worldPos - _textDragPointerStart!;
    if (delta.distance > 4) _textDragMoved = true;
    setState(() {
      _textLabels[_draggedTextLabelIndex!].position = _textDragLabelStart! + delta;
    });
  }

  /// If the pointer never actually moved, treat it as a tap instead of a
  /// drag and open that label for editing rather than just "moving" it in
  /// place.
  void _endTextLabelDrag() {
    if (_draggedTextLabelIndex == null) return;
    final int idx = _draggedTextLabelIndex!;
    final bool moved = _textDragMoved;
    _draggedTextLabelIndex = null;
    _textDragPointerStart = null;
    _textDragLabelStart = null;
    _textDragMoved = false;
    if (!moved) {
      _openTextEditor(editingIndex: idx);
    }
  }

  void _openTextEditor({int? editingIndex, Offset? newPosition}) {
    setState(() {
      _textEditingIndex = editingIndex;
      _textEditorWorldPos = editingIndex != null
          ? _textLabels[editingIndex].position
          : newPosition;
      _textEditorController = TextEditingController(
        text: editingIndex != null ? _textLabels[editingIndex].text : '',
      );
      _textEditorOpen = true;
    });
  }

  void _commitTextEditor() {
    if (!_textEditorOpen) return;
    final String value = _textEditorController?.text.trim() ?? '';
    final int? editingIndex = _textEditingIndex;
    final Offset? newPosition = _textEditorWorldPos;
    setState(() {
      if (editingIndex != null) {
        if (value.isEmpty) {
          _textLabels.removeAt(editingIndex);
        } else {
          _textLabels[editingIndex].text = value;
        }
      } else if (value.isNotEmpty && newPosition != null) {
        _textLabels.add(
          MathsPadTextLabel(
            position: newPosition,
            text: value,
            color: _selectedColor,
          ),
        );
      }
      _textEditorController?.dispose();
      _textEditorController = null;
      _textEditorOpen = false;
      _textEditingIndex = null;
      _textEditorWorldPos = null;
    });
  }

  void _deleteTextLabel(int index) {
    setState(() {
      _textLabels.removeAt(index);
    });
  }

  bool _tryStartInstrumentDrag(Offset worldPos) {
    final hit = _hitTestInstrumentHandles(worldPos);
    if (hit == null) return false;
    final (inst, handle) = hit;

    _draggedInstrument = inst;
    _draggedHandle = handle;
    _instrumentDragStartWorld = worldPos;
    _instrumentDragStartPivot = inst.pivot;
    _instrumentDragStartRotation = inst.rotation;
    _pencilDragMoved = false;
    if (inst is ProtractorState) _instrumentDragStartRadiusOrScale = inst.radius;
    if (inst is SetSquareState) _instrumentDragStartRadiusOrScale = inst.scale;
    if (inst is CompassState && handle == 'tip' && inst.locked) {
      inst.tracedArcPoints = [inst.tipWorldPosition];
      _lastCompassTracePoint = inst.tipWorldPosition;
    }
    return true;
  }

  void _updateCompassAngle(
    CompassState c,
    Offset worldPos, {
    required bool allowRadiusChange,
  }) {
    final vector = worldPos - c.pivot;
    if (vector.distance < 1) return;
    c.armAngle = vector.direction;

    if (c.locked) {
      final tip = c.tipWorldPosition;
      if (_lastCompassTracePoint == null ||
          (tip - _lastCompassTracePoint!).distance >= 1.2) {
        c.tracedArcPoints.add(tip);
        _lastCompassTracePoint = tip;
      }
    } else if (allowRadiusChange) {
      c.radiusCm = (vector.distance / kPxPerCm).clamp(0.5, 30.0);
    }
  }

  void _updateInstrumentDrag(Offset worldPos) {
    final inst = _draggedInstrument;
    final handle = _draggedHandle;
    if (inst == null || handle == null) return;

    setState(() {
      if (inst is CompassState && handle == 'pivot') {
        final delta = worldPos - _instrumentDragStartWorld!;
        inst.pivot = _instrumentDragStartPivot! + delta;
      } else if (inst is CompassState && handle == 'hinge') {
        _updateCompassAngle(inst, worldPos, allowRadiusChange: false);
      } else if (inst is CompassState && handle == 'tip') {
        _updateCompassAngle(inst, worldPos, allowRadiusChange: !inst.locked);
      } else if (handle == 'move') {
        final delta = worldPos - _instrumentDragStartWorld!;
        inst.pivot = _instrumentDragStartPivot! + delta;
      } else if (handle == 'rotate') {
        final startVec = _instrumentDragStartWorld! - _instrumentDragStartPivot!;
        final currentVec = worldPos - inst.pivot;
        inst.rotation =
            _instrumentDragStartRotation! +
            (currentVec.direction - startVec.direction);
      } else if (handle == 'resize') {
        final startDist =
            (_instrumentDragStartWorld! - _instrumentDragStartPivot!).distance;
        final currentDist = (worldPos - inst.pivot).distance;
        if (startDist > 1) {
          final factor = currentDist / startDist;
          if (inst is ProtractorState) {
            inst.radius =
                (_instrumentDragStartRadiusOrScale! * factor).clamp(50.0, 400.0);
          } else if (inst is SetSquareState) {
            inst.scale =
                (_instrumentDragStartRadiusOrScale! * factor).clamp(0.4, 3.0);
          }
        }
      } else if (handle == 'pencil') {
        // The attached drawing pencil: a plain tap (no real movement) arms
        // it (turns blue); dragging it -- armed or not -- slides it along
        // the instrument's ruled edge (for a Set Square, whichever of its
        // three edges is currently closest), and while armed that same
        // drag also draws a straight line snapped to the edge's exact
        // angle.
        final edge = _resolvePencilEdge(inst, worldPos);
        if (edge != null) {
          final onSegment = _projectPointOntoSegment(worldPos, edge.$1, edge.$2);
          final distFromEdgeStart = (onSegment - edge.$1).distance;
          if (inst is RulerState) inst.pencilOffsetPx = distFromEdgeStart;
          if (inst is SetSquareState) inst.pencilOffsetPx = distFromEdgeStart;

          final movedDist = (worldPos - _instrumentDragStartWorld!).distance;
          if (movedDist > 6) {
            _pencilDragMoved = true;
            if (_isPencilArmed(inst)) {
              if (_currentLine == null) {
                final start = _projectPointOntoSegment(
                  _instrumentDragStartWorld!,
                  edge.$1,
                  edge.$2,
                );
                _snappedEdgeStart = start;
                _snappedEdgeVector = edge.$2 - edge.$1;
                _currentLine = MathsPadLine(
                  points: [MathsPadStrokePoint(start)],
                  color: _selectedColor,
                  strokeWidth: _penWidth,
                );
              }
              final end = _projectPointOntoInfiniteLine(
                worldPos,
                _snappedEdgeStart!,
                _snappedEdgeVector!,
              );
              _currentLine!.points
                ..clear()
                ..add(MathsPadStrokePoint(_snappedEdgeStart!))
                ..add(MathsPadStrokePoint(end));
              _activeDrawingNotifier.value++;
            }
          }
        }
      }
    });
  }

  void _endInstrumentDrag() {
    final inst = _draggedInstrument;
    final handle = _draggedHandle;

    if (inst is CompassState && inst.locked && inst.tracedArcPoints.length > 1) {
      _commitCompassArc(List<Offset>.from(inst.tracedArcPoints));
    }
    if (inst is CompassState) {
      inst.tracedArcPoints = [];
    }

    if (inst != null && handle == 'pencil') {
      if (!_pencilDragMoved) {
        _togglePencilArmed(inst);
      } else if (_currentLine != null) {
        _currentLine!.invalidateCache();
        _lines.add(_currentLine!);
        _finishedStrokesNotifier.value++;
        _currentLine = null;
      }
    }

    setState(() {
      _draggedInstrument = null;
      _draggedHandle = null;
      _lastCompassTracePoint = null;
      _snappedEdgeStart = null;
      _snappedEdgeVector = null;
      _pencilDragMoved = false;
    });
  }

  // Calculate Group Bounding Box Rect for active selection
  Rect? _getSelectionBounds() {
    if (_selectedLines.isEmpty) return null;
    double minX = double.infinity;
    double maxX = -double.infinity;
    double minY = double.infinity;
    double maxY = -double.infinity;

    for (final line in _selectedLines) {
      for (final p in line.points) {
        if (p.offset.dx < minX) minX = p.offset.dx;
        if (p.offset.dx > maxX) maxX = p.offset.dx;
        if (p.offset.dy < minY) minY = p.offset.dy;
        if (p.offset.dy > maxY) maxY = p.offset.dy;
      }
    }

    if (minX == double.infinity) return null;
    return Rect.fromLTRB(minX, minY, maxX, maxY).inflate(16.0);
  }

  // Hit-test selection controls (Rotation Handle, 4 Corner Resize Handles, Move Area)
  SelectionHandleType _hitTestSelectionHandles(Offset worldPos, Rect bounds) {
    final double hitR = 18.0 / _scale;

    // Check Rotation Handle (Top Center, 28px above top border)
    final Offset rotHandlePos = Offset(
      bounds.center.dx,
      bounds.top - 28.0 / _scale,
    );
    if ((worldPos - rotHandlePos).distance <= hitR) {
      return SelectionHandleType.rotate;
    }

    // Check 4 Corner Resize Handles
    if ((worldPos - bounds.topLeft).distance <= hitR) {
      return SelectionHandleType.topLeft;
    }
    if ((worldPos - bounds.topRight).distance <= hitR) {
      return SelectionHandleType.topRight;
    }
    if ((worldPos - bounds.bottomLeft).distance <= hitR) {
      return SelectionHandleType.bottomLeft;
    }
    if ((worldPos - bounds.bottomRight).distance <= hitR) {
      return SelectionHandleType.bottomRight;
    }

    // Check inside bounding box for Move Translation
    if (bounds.contains(worldPos)) {
      return SelectionHandleType.move;
    }

    return SelectionHandleType.none;
  }

  // Find opposite corner anchor point for proportional scaling
  Offset _getResizeAnchor(SelectionHandleType handle, Rect bounds) {
    switch (handle) {
      case SelectionHandleType.topLeft:
        return bounds.bottomRight;
      case SelectionHandleType.topRight:
        return bounds.bottomLeft;
      case SelectionHandleType.bottomLeft:
        return bounds.topRight;
      case SelectionHandleType.bottomRight:
        return bounds.topLeft;
      default:
        return bounds.center;
    }
  }

  double _distToSegment(Offset p, Offset v, Offset w) {
    final double l2 = (v - w).distanceSquared;
    if (l2 == 0) return (p - v).distance;
    double t =
        ((p.dx - v.dx) * (w.dx - v.dx) + (p.dy - v.dy) * (w.dy - v.dy)) / l2;
    t = t.clamp(0.0, 1.0);
    final Offset proj = Offset(
      v.dx + t * (w.dx - v.dx),
      v.dy + t * (w.dy - v.dy),
    );
    return (p - proj).distance;
  }

  // Find drawn stroke line closest to tapped world position
  MathsPadLine? _findLineAt(Offset worldPos) {
    for (int i = _lines.length - 1; i >= 0; i--) {
      final line = _lines[i];
      if (line.isEraser) continue;
      final double hitRadius = (line.strokeWidth + 14.0) / _scale;

      if (line.points.length == 1) {
        if ((line.points.first.offset - worldPos).distance <= hitRadius) {
          return line;
        }
      } else {
        for (int j = 0; j < line.points.length - 1; j++) {
          final p1 = line.points[j].offset;
          final p2 = line.points[j + 1].offset;
          if (_distToSegment(worldPos, p1, p2) <= hitRadius) {
            return line;
          }
        }
      }
    }
    return null;
  }

  void _updatePointerPos(Offset localPosition) {
    final newWorldPos = _screenToWorld(localPosition);
    if (_lastPointerWorldPos == null ||
        (_lastPointerWorldPos! - newWorldPos).distance > 5.0) {
      _consecutivePasteCount = 0;
    }
    _lastPointerWorldPos = newWorldPos;
  }

  void _onPointerHover(PointerHoverEvent event) {
    _updatePointerPos(event.localPosition);
  }

  void _onPointerDown(PointerDownEvent event) {
    _frictionController?.stop();
    _updatePointerPos(event.localPosition);
    _activePointers[event.pointer] = event.localPosition;
    _lastCentroid = _calculateCentroid();

    final bool isBarrelOrInverted =
        event.kind == PointerDeviceKind.invertedStylus ||
        (event.buttons & kSecondaryButton != 0) ||
        (event.buttons & kTertiaryButton != 0);
    if (_isStylusBarrelPressed != isBarrelOrInverted) {
      setState(() {
        _isStylusBarrelPressed = isBarrelOrInverted;
      });
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    _updatePointerPos(event.localPosition);
    if (_activePointers.containsKey(event.pointer)) {
      _activePointers[event.pointer] = event.localPosition;

      // Chrome Web Multi-Touch 2-finger pan
      if (_activePointers.length >= 2) {
        if (_currentLine != null) {
          if (_lines.isNotEmpty && _lines.last == _currentLine) {
            _lines.removeLast();
          }
          _currentLine = null;
        }
        _lassoPoints.clear();

        if (_lastCentroid != null) {
          final currentCentroid = _calculateCentroid();
          final delta = currentCentroid - _lastCentroid!;
          // Directly update notifier – zero rebuild, maximum frame rate
          _panOffset += delta;
          _panNotifier.value = _panOffset;
          _lastCentroid = currentCentroid;
        } else {
          _lastCentroid = _calculateCentroid();
        }
        return;
      }
    }

    final bool isBarrelOrInverted =
        event.kind == PointerDeviceKind.invertedStylus ||
        (event.buttons & kSecondaryButton != 0) ||
        (event.buttons & kTertiaryButton != 0);
    if (_isStylusBarrelPressed != isBarrelOrInverted) {
      setState(() {
        _isStylusBarrelPressed = isBarrelOrInverted;
      });
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);
    if (_activePointers.isEmpty) {
      _lastCentroid = null;
    }

    if (_isStylusBarrelPressed) {
      setState(() {
        _isStylusBarrelPressed = false;
      });
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _activePointers.remove(event.pointer);
    if (_activePointers.isEmpty) {
      _lastCentroid = null;
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (widget.isTransparentBg) return;
    if (event is PointerScrollEvent) {
      _frictionController?.stop();

      if (_currentLine != null) {
        if (_lines.isNotEmpty && _lines.last == _currentLine) {
          _lines.removeLast();
        }
        _currentLine = null;
      }

      final isControlPressed = HardwareKeyboard.instance.isControlPressed;
      if (isControlPressed) {
        // Pinch-to-zoom on Chrome trackpad or Ctrl + Wheel
        setState(() {
          final double zoomFactor = event.scrollDelta.dy > 0 ? 0.93 : 1.07;
          _scale = (_scale * zoomFactor).clamp(0.25, 4.0);
        });
      } else {
        // Butter-smooth 1.35x 360-degree trackpad pan – direct notifier, 0 rebuilds!
        final Offset delta =
            Offset(-event.scrollDelta.dx, -event.scrollDelta.dy) * 1.35;
        _panOffset += delta;
        _panNotifier.value = _panOffset;
      }
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    _frictionController?.stop();
    if (widget.isTransparentBg) {
      _panOffset = Offset.zero;
      _scale = 1.0;
      _panNotifier.value = Offset.zero;
      _scaleNotifier.value = 1.0;
    }
    _initialFocalPoint = details.localFocalPoint;
    _initialPanOffset = _panOffset;
    _initialScale = _scale;

    // 2-finger touch is dedicated to canvas panning and zooming
    if (details.pointerCount > 1 || _activePointers.length >= 2) {
      if (_currentLine != null) {
        if (_lines.isNotEmpty && _lines.last == _currentLine) {
          _lines.removeLast();
        }
        _currentLine = null;
      }
      _lassoPoints.clear();
      return;
    }

    if (details.pointerCount == 1 && _toolMode != CanvasToolMode.pan) {
      final worldPos = _screenToWorld(details.localFocalPoint);

      // Any tap while the text editor is open commits/closes it first,
      // rather than also acting on whatever else was tapped.
      if (_textEditorOpen) {
        _commitTextEditor();
        return;
      }

      // Geometry instrument handles (move/rotate/resize, or the compass's
      // pivot/hinge/tip) always take priority over the current drawing
      // tool, so instruments stay adjustable no matter what's selected.
      if (_tryStartInstrumentDrag(worldPos)) {
        return;
      }

      // Existing text labels are always draggable/editable too, regardless
      // of the active tool -- same priority as instruments.
      if (_tryStartTextLabelDrag(worldPos)) {
        return;
      }

      if (_toolMode == CanvasToolMode.text) {
        _openTextEditor(newPosition: worldPos);
        return;
      }

      if (_toolMode == CanvasToolMode.straightLine) {
        _handleStraightLineToolStart(worldPos);
        _undoHistory.clear();
        _selectedLines.clear();
        _activeDrawingNotifier.value++;
        return;
      }

      if (_toolMode == CanvasToolMode.spacer) {
        _handleSpacerToolStart(worldPos);
        _undoHistory.clear();
        _selectedLines.clear();
        return;
      }

      if (_toolMode == CanvasToolMode.angle) {
        _handleAngleToolStart(worldPos);
        _undoHistory.clear();
        _selectedLines.clear();
        _activeDrawingNotifier.value++;
        return;
      }

      if (_toolMode == CanvasToolMode.polygonAngle) {
        _handlePolygonToolStart(worldPos);
        _undoHistory.clear();
        _selectedLines.clear();
        _activeDrawingNotifier.value++;
        return;
      }

      if (_toolMode == CanvasToolMode.circleArc) {
        _handleCircleArcToolStart(worldPos);
        _undoHistory.clear();
        _selectedLines.clear();
        _activeDrawingNotifier.value++;
        return;
      }

      if (_toolMode == CanvasToolMode.fill) {
        // A tap-and-release action, not a drag -- handled entirely here.
        _undoHistory.clear();
        _selectedLines.clear();
        _performBucketFill(details.localFocalPoint);
        return;
      }

      if (_activeShapeTool != null) {
        _shapeDragStartPos = worldPos;
        _shapeDragCurrentPos = worldPos;
        _selectedLines.clear();
        return;
      }

      // Check if user is touching selection bounds or control handles (Move, Resize, Rotate)
      final selectionBounds = _getSelectionBounds();
      if (selectionBounds != null) {
        final handle = _hitTestSelectionHandles(worldPos, selectionBounds);
        if (handle != SelectionHandleType.none) {
          _activeHandle = handle;
          _transformStartPos = worldPos;
          _transformCenter = selectionBounds.center;

          if (handle == SelectionHandleType.rotate) {
            _initialAngle = atan2(
              worldPos.dy - _transformCenter!.dy,
              worldPos.dx - _transformCenter!.dx,
            );
          } else if (handle != SelectionHandleType.move) {
            final Offset anchor = _getResizeAnchor(handle, selectionBounds);
            _initialScaleDist = (worldPos - anchor).distance;
            if (_initialScaleDist == 0) _initialScaleDist = 1.0;
          }
          return;
        }
      }

      _activeHandle = SelectionHandleType.none;
      _transformStartPos = null;
      _transformCenter = null;

      if (_toolMode == CanvasToolMode.tapSelect) {
        final hitLine = _findLineAt(worldPos);
        setState(() {
          if (hitLine != null) {
            if (_selectedLines.contains(hitLine)) {
              _selectedLines.remove(hitLine);
            } else {
              _selectedLines.add(hitLine);
            }
          } else {
            _selectedLines.clear();
          }
        });
      } else if (_toolMode == CanvasToolMode.lasso) {
        setState(() {
          _lassoPoints = [worldPos];
          _selectedLines.clear();
        });
      } else if ((_toolMode == CanvasToolMode.eraser ||
              _isStylusBarrelPressed) &&
          _eraserMode == EraserMode.stroke) {
        // Stroke Eraser Mode: Tapping on a stroke line immediately erases the whole line!
        final hitLine = _findLineAt(worldPos);
        if (hitLine != null) {
          setState(() {
            _undoHistory.add(hitLine);
            _lines.remove(hitLine);
            _selectedLines.remove(hitLine);
            _removeOrphanedAngleLabels([hitLine]);
          });
        }
      } else {
        final bool isEraserStroke =
            _toolMode == CanvasToolMode.eraser || _isStylusBarrelPressed;
        final double activeWidth = isEraserStroke ? _eraserWidth : _penWidth;

        final newLine = MathsPadLine(
          points: [MathsPadStrokePoint(worldPos)],
          color: _selectedColor,
          strokeWidth: activeWidth,
          isEraser: isEraserStroke,
        );
        _currentLine = newLine;
        _undoHistory.clear();
        _selectedLines.clear();
        _activeDrawingNotifier.value++;
      }
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    // 2-finger pinch/drag OR Hand/Pan tool -> Infinite Canvas Panning & Zooming
    if (!widget.isTransparentBg &&
        (details.pointerCount > 1 ||
            _activePointers.length >= 2 ||
            _toolMode == CanvasToolMode.pan)) {
      if (_currentLine != null) {
        if (_lines.isNotEmpty && _lines.last == _currentLine) {
          _lines.removeLast();
        }
        _currentLine = null;
      }
      _lassoPoints.clear();

      // Direct notifier updates – no setState → zero widget-tree rebuild at 120fps!
      _scale = (_initialScale * details.scale).clamp(0.25, 4.0);
      final focalDelta = details.localFocalPoint - _initialFocalPoint;
      _panOffset = _initialPanOffset + focalDelta;
      _panNotifier.value = _panOffset;
      _scaleNotifier.value = _scale;
      return;
    } else if (_draggedInstrument != null) {
      _updateInstrumentDrag(_screenToWorld(details.localFocalPoint));
      return;
    } else if (_draggedTextLabelIndex != null) {
      _updateTextLabelDrag(_screenToWorld(details.localFocalPoint));
      return;
    } else if (_activeShapeTool != null && _shapeDragStartPos != null) {
      final worldPos = _screenToWorld(details.localFocalPoint);
      _shapeDragCurrentPos = worldPos;
      _activeDrawingNotifier.value++;
      return;
    } else if (_activeHandle != SelectionHandleType.none &&
        _transformStartPos != null) {
      // Active Selection Transformation: Move, Resize (Scale), or Rotate
      final worldPos = _screenToWorld(details.localFocalPoint);

      if (_activeHandle == SelectionHandleType.move) {
        final delta = worldPos - _transformStartPos!;
        for (final line in _selectedLines) {
          for (int i = 0; i < line.points.length; i++) {
            line.points[i].offset += delta;
          }
          line.invalidateCache();
        }
        _transformStartPos = worldPos;
        _finishedStrokesNotifier.value++;
        _activeDrawingNotifier.value++;
      } else if (_activeHandle == SelectionHandleType.rotate &&
          _transformCenter != null) {
        final double currentAngle = atan2(
          worldPos.dy - _transformCenter!.dy,
          worldPos.dx - _transformCenter!.dx,
        );
        final double angleDelta = currentAngle - _initialAngle;
        _initialAngle = currentAngle;

        final double cosA = cos(angleDelta);
        final double sinA = sin(angleDelta);

        for (final line in _selectedLines) {
          if (line.points.isEmpty) continue;
          // A Fill Tool region is a raster image, not a real stroke -- there's
          // no way to rotate its pixels here, so leave it stationary rather
          // than rotating just its bounding corner points (which would only
          // skew the rect, not actually rotate the image).
          if (line.fillImage != null) continue;

          // Calculate individual stroke center (centroid of this line's points)
          double sumX = 0;
          double sumY = 0;
          for (final p in line.points) {
            sumX += p.offset.dx;
            sumY += p.offset.dy;
          }
          final Offset lineCenter = Offset(
            sumX / line.points.length,
            sumY / line.points.length,
          );

          // Rotate each stroke around its OWN individual center!
          for (int i = 0; i < line.points.length; i++) {
            final loc = line.points[i].offset - lineCenter;
            final rotX = loc.dx * cosA - loc.dy * sinA;
            final rotY = loc.dx * sinA + loc.dy * cosA;
            line.points[i].offset = lineCenter + Offset(rotX, rotY);
          }
          line.invalidateCache();
        }
        _finishedStrokesNotifier.value++;
        _activeDrawingNotifier.value++;
      } else {
        // Corner Resize (Scale) Mode
        final selectionBounds = _getSelectionBounds();
        if (selectionBounds != null) {
          final Offset anchor = _getResizeAnchor(
            _activeHandle,
            selectionBounds,
          );
          final double currentDist = (worldPos - anchor).distance;
          final double scaleFactor =
              (currentDist / (_initialScaleDist == 0 ? 1.0 : _initialScaleDist))
                  .clamp(0.05, 20.0);
          _initialScaleDist = currentDist;

          for (final line in _selectedLines) {
            for (int i = 0; i < line.points.length; i++) {
              line.points[i].offset =
                  anchor + (line.points[i].offset - anchor) * scaleFactor;
            }
            line.invalidateCache();
          }
          _finishedStrokesNotifier.value++;
          _activeDrawingNotifier.value++;
        }
      }
      return;
    } else if ((_toolMode == CanvasToolMode.eraser || _isStylusBarrelPressed) &&
        _eraserMode == EraserMode.stroke) {
      // Stroke Eraser Mode: Dragging across stroke lines erases each whole line touched
      final worldPos = _screenToWorld(details.localFocalPoint);
      final hitLine = _findLineAt(worldPos);
      if (hitLine != null) {
        _undoHistory.add(hitLine);
        _lines.remove(hitLine);
        _selectedLines.remove(hitLine);
        _removeOrphanedAngleLabels([hitLine]);
        _finishedStrokesNotifier.value++;
        _activeDrawingNotifier.value++;
      }
      return;
    } else if (_isDraggingSelection && _lastDragWorldPos != null) {
      // Moving/dragging selected items in real time
      final worldPos = _screenToWorld(details.localFocalPoint);
      final delta = worldPos - _lastDragWorldPos!;
      for (final line in _selectedLines) {
        for (int i = 0; i < line.points.length; i++) {
          line.points[i].offset += delta;
        }
        line.invalidateCache();
      }
      _lastDragWorldPos = worldPos;
      _finishedStrokesNotifier.value++;
      _activeDrawingNotifier.value++;
    } else if (_toolMode == CanvasToolMode.lasso && _lassoPoints.isNotEmpty) {
      final worldPos = _screenToWorld(details.localFocalPoint);
      _lassoPoints.add(worldPos);
      _activeDrawingNotifier.value++;
    } else if (_toolMode == CanvasToolMode.straightLine &&
        _currentLine != null) {
      // setState needed for the same reason as the other tools' live badges
      // below: the instruments-overlay Stack only rebuilds on pan/zoom or a
      // real setState, not on `_activeDrawingNotifier`.
      setState(() {
        _handleStraightLineToolUpdate(_screenToWorld(details.localFocalPoint));
      });
    } else if (_toolMode == CanvasToolMode.spacer &&
        _spacerPointerStart != null) {
      setState(() {
        _handleSpacerToolUpdate(_screenToWorld(details.localFocalPoint));
      });
    } else if (_toolMode == CanvasToolMode.angle && _currentLine != null) {
      // setState (not just the notifier bump inside the handler) is needed
      // here because the live angle badge lives in the instruments-overlay
      // Stack, which only rebuilds on pan/zoom or a real setState -- not on
      // `_activeDrawingNotifier` (that only repaints the stroke itself).
      setState(() {
        _handleAngleToolUpdate(_screenToWorld(details.localFocalPoint));
      });
    } else if (_toolMode == CanvasToolMode.polygonAngle && _currentLine != null) {
      setState(() {
        _handlePolygonToolUpdate(_screenToWorld(details.localFocalPoint));
      });
    } else if (_toolMode == CanvasToolMode.circleArc && _currentLine != null) {
      // setState needed (same reason as the angle tools above): the live
      // length badge lives in the instruments-overlay Stack, which only
      // rebuilds on pan/zoom or a real setState, not on `_activeDrawingNotifier`.
      setState(() {
        _handleCircleArcToolUpdate(_screenToWorld(details.localFocalPoint));
      });
    } else if (_currentLine != null) {
      // 1-finger freehand drawing stroke update
      final worldPos = _screenToWorld(details.localFocalPoint);
      if (_currentLine!.points.isEmpty ||
          (worldPos - _currentLine!.points.last.offset).distance >= 1.2) {
        _currentLine!.points.add(MathsPadStrokePoint(worldPos));
        if (_currentLine!.isEraser) {
          _finishedStrokesNotifier.value++;
        }
        _activeDrawingNotifier.value++;
      }
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_draggedInstrument != null) {
      _endInstrumentDrag();
      return;
    }
    if (_draggedTextLabelIndex != null) {
      _endTextLabelDrag();
      return;
    }
    if (_toolMode == CanvasToolMode.straightLine && _currentLine != null) {
      setState(() {
        _handleStraightLineToolEnd();
      });
      return;
    }
    if (_toolMode == CanvasToolMode.spacer) {
      setState(() {
        _handleSpacerToolEnd();
      });
      return;
    }
    if (_toolMode == CanvasToolMode.angle && _currentLine != null) {
      setState(() {
        _handleAngleToolEnd();
      });
      return;
    }
    if (_toolMode == CanvasToolMode.polygonAngle && _currentLine != null) {
      setState(() {
        _handlePolygonToolEnd();
      });
      return;
    }
    if (_toolMode == CanvasToolMode.circleArc) {
      setState(() {
        _handleCircleArcToolEnd();
      });
      return;
    }
    if (_activeShapeTool != null &&
        _shapeDragStartPos != null &&
        _shapeDragCurrentPos != null) {
      final Rect shapeRect = Rect.fromPoints(
        _shapeDragStartPos!,
        _shapeDragCurrentPos!,
      );
      if (shapeRect.width.abs() > 4 && shapeRect.height.abs() > 4) {
        final newShapeLines = generateShapeLinesInRect(
          _activeShapeTool!,
          shapeRect,
          _selectedColor,
          _penWidth,
        );

        for (final line in newShapeLines) {
          _buildAndCachePath(line);
        }

        setState(() {
          _lines.addAll(newShapeLines);
          _selectedLines.clear();
          _selectedLines.addAll(newShapeLines);
          _toolMode = CanvasToolMode.pen;
          _selectedWidth = _penWidth;
          _activeShapeTool = null;
        });
        _finishedStrokesNotifier.value++;
        _activeDrawingNotifier.value++;
      }
      _shapeDragStartPos = null;
      _shapeDragCurrentPos = null;
      return;
    }

    _activeHandle = SelectionHandleType.none;
    _transformStartPos = null;
    _transformCenter = null;

    if (_isDraggingSelection) {
      _isDraggingSelection = false;
      _lastDragWorldPos = null;
      for (final line in _selectedLines) {
        _buildAndCachePath(line);
      }
      _finishedStrokesNotifier.value++;
      return;
    }

    // Perform Lasso Selection: enclosed strokes become selected for Move or Duplicate
    if (_toolMode == CanvasToolMode.lasso && _lassoPoints.length > 2) {
      final lassoPath = Path();
      lassoPath.moveTo(_lassoPoints.first.dx, _lassoPoints.first.dy);
      for (int i = 1; i < _lassoPoints.length; i++) {
        lassoPath.lineTo(_lassoPoints[i].dx, _lassoPoints[i].dy);
      }
      lassoPath.close();

      final Set<MathsPadLine> selectedContained = {};

      for (final line in _lines) {
        for (final point in line.points) {
          if (lassoPath.contains(point.offset)) {
            selectedContained.add(line);
            break;
          }
        }
      }

      setState(() {
        _selectedLines.clear();
        _selectedLines.addAll(selectedContained);
        _lassoPoints = [];
      });
      _activeDrawingNotifier.value++;
    }

    // Trigger smooth inertial gliding velocity physics when flinging 2 fingers or Hand Tool
    if (_toolMode == CanvasToolMode.pan || _activePointers.length >= 2) {
      _startInertialFling(details.velocity.pixelsPerSecond);
    }

    if (_currentLine != null) {
      _currentLine!.invalidateCache();
      _buildAndCachePath(_currentLine!);
      _lines.add(_currentLine!);
      _currentLine = null;
      _finishedStrokesNotifier.value++;
      _activeDrawingNotifier.value++;
    }
    _snappedEdgeStart = null;
    _snappedEdgeVector = null;
  }

  void _handleEraserButtonTap() {
    final now = DateTime.now();
    final isDoubleClick =
        _lastEraserClickTime != null &&
        now.difference(_lastEraserClickTime!).inMilliseconds < 450;
    _lastEraserClickTime = now;

    setState(() {
      if (_toolMode == CanvasToolMode.eraser) {
        // Tapping again while active or double-clicking toggles Eraser Mode (Stroke <-> Area)
        _eraserMode = (_eraserMode == EraserMode.stroke)
            ? EraserMode.area
            : EraserMode.stroke;
      } else {
        _toolMode = CanvasToolMode.eraser;
        if (isDoubleClick) {
          _eraserMode = EraserMode.stroke;
        }
      }
      _selectedWidth = _eraserWidth;
      _selectedLines.clear();
    });
  }

  // Copy selected strokes into clipboard (Ctrl+C)
  void _copySelectedLines() {
    if (_selectedLines.isEmpty) return;
    setState(() {
      _clipboard = _selectedLines.map((line) {
        return MathsPadLine(
          points: line.points.map((p) => MathsPadStrokePoint(p.offset)).toList(),
          color: line.color,
          strokeWidth: line.strokeWidth,
          isEraser: line.isEraser,
          isShape: line.isShape,
          fillImage: line.fillImage,
          fillWorldBounds: line.fillWorldBounds,
        );
      }).toList();
    });
  }

  Offset _getClipboardCenter() {
    if (_clipboard.isEmpty) return Offset.zero;
    double minX = double.infinity;
    double maxX = -double.infinity;
    double minY = double.infinity;
    double maxY = -double.infinity;

    for (final line in _clipboard) {
      for (final p in line.points) {
        if (p.offset.dx < minX) minX = p.offset.dx;
        if (p.offset.dx > maxX) maxX = p.offset.dx;
        if (p.offset.dy < minY) minY = p.offset.dy;
        if (p.offset.dy > maxY) maxY = p.offset.dy;
      }
    }

    if (minX == double.infinity) return Offset.zero;
    return Offset((minX + maxX) / 2, (minY + maxY) / 2);
  }

  // Paste clipboard strokes at pointer location (Ctrl+V)
  void _pasteClipboard() {
    if (_clipboard.isEmpty) return;

    final Offset clipboardCenter = _getClipboardCenter();
    Offset targetCenter;

    if (_lastPointerWorldPos != null) {
      targetCenter = _lastPointerWorldPos!;
    } else {
      targetCenter = _screenToWorld(const Offset(400.0, 300.0));
    }

    // Apply a small offset for consecutive pastes at the exact same location
    final Offset stepOffset = Offset(
      20.0 * _consecutivePasteCount,
      20.0 * _consecutivePasteCount,
    );
    _consecutivePasteCount++;

    final Offset translation = (targetCenter + stepOffset) - clipboardCenter;

    final List<MathsPadLine> pasted = _clipboard.map((line) {
      final newLine = MathsPadLine(
        points: line.points
            .map((p) => MathsPadStrokePoint(p.offset + translation))
            .toList(),
        color: line.color,
        strokeWidth: line.strokeWidth,
        isEraser: line.isEraser,
        isShape: line.isShape,
        fillImage: line.fillImage,
        fillWorldBounds: line.fillWorldBounds?.shift(translation),
      );
      _buildAndCachePath(newLine);
      return newLine;
    }).toList();

    setState(() {
      _lines.addAll(pasted);
      _undoHistory.clear();
      _selectedLines.clear();
      _selectedLines.addAll(pasted);
    });
    _finishedStrokesNotifier.value++;
  }

  // Duplicate Selected Strokes
  void _duplicateSelectedLines() {
    if (_selectedLines.isEmpty) return;

    final List<MathsPadLine> duplicatedLines = [];
    const Offset copyOffset = Offset(25.0, 25.0);

    for (final line in _selectedLines) {
      final newPoints = line.points
          .map((p) => MathsPadStrokePoint(p.offset + copyOffset))
          .toList();
      final newLine = MathsPadLine(
        points: newPoints,
        color: line.color,
        strokeWidth: line.strokeWidth,
        isEraser: line.isEraser,
        fillImage: line.fillImage,
        fillWorldBounds: line.fillWorldBounds?.shift(copyOffset),
      );
      _buildAndCachePath(newLine);
      duplicatedLines.add(newLine);
    }

    setState(() {
      _lines.addAll(duplicatedLines);
      _undoHistory.addAll(duplicatedLines);
      _selectedLines.clear();
      _selectedLines.addAll(duplicatedLines);
    });
    _finishedStrokesNotifier.value++;
  }

  void _deleteSelectedLines() {
    if (_selectedLines.isNotEmpty) {
      setState(() {
        _undoHistory.addAll(_selectedLines);
        _lines.removeWhere((line) => _selectedLines.contains(line));
        _removeOrphanedAngleLabels(_selectedLines);
        _selectedLines.clear();
      });
      _finishedStrokesNotifier.value++;
    }
  }

  static List<MathsPadLine> generateShapeLinesInRect(
    BasicShapeType shapeType,
    Rect rect,
    Color color,
    double strokeWidth,
  ) {
    final List<MathsPadLine> createdLines = [];
    final Offset center = rect.center;
    final double radiusX = rect.width.abs() / 2;
    final double radiusY = rect.height.abs() / 2;

    switch (shapeType) {
      case BasicShapeType.circle:
        final List<MathsPadStrokePoint> pts = [];
        for (int i = 0; i <= 64; i++) {
          final double a = (i / 64) * 2 * pi;
          pts.add(
            MathsPadStrokePoint(center + Offset(cos(a) * radiusX, sin(a) * radiusY)),
          );
        }
        createdLines.add(
          MathsPadLine(
            points: pts,
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        break;

      case BasicShapeType.square:
        final double side = min(rect.width.abs(), rect.height.abs()) / 2;
        final squareRect = Rect.fromCircle(center: center, radius: side);
        final pts = [
          MathsPadStrokePoint(squareRect.topLeft),
          MathsPadStrokePoint(squareRect.topRight),
          MathsPadStrokePoint(squareRect.bottomRight),
          MathsPadStrokePoint(squareRect.bottomLeft),
          MathsPadStrokePoint(squareRect.topLeft),
        ];
        createdLines.add(
          MathsPadLine(
            points: pts,
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        break;

      case BasicShapeType.rectangle:
        final pts = [
          MathsPadStrokePoint(rect.topLeft),
          MathsPadStrokePoint(rect.topRight),
          MathsPadStrokePoint(rect.bottomRight),
          MathsPadStrokePoint(rect.bottomLeft),
          MathsPadStrokePoint(rect.topLeft),
        ];
        createdLines.add(
          MathsPadLine(
            points: pts,
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        break;

      case BasicShapeType.triangle:
        final pts = [
          MathsPadStrokePoint(Offset(center.dx, rect.top)),
          MathsPadStrokePoint(rect.bottomRight),
          MathsPadStrokePoint(rect.bottomLeft),
          MathsPadStrokePoint(Offset(center.dx, rect.top)),
        ];
        createdLines.add(
          MathsPadLine(
            points: pts,
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        break;

      case BasicShapeType.rightTriangle:
        final pts = [
          MathsPadStrokePoint(rect.bottomLeft),
          MathsPadStrokePoint(rect.bottomRight),
          MathsPadStrokePoint(rect.topLeft),
          MathsPadStrokePoint(rect.bottomLeft),
        ];
        createdLines.add(
          MathsPadLine(
            points: pts,
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        break;

      case BasicShapeType.pentagon:
        final List<MathsPadStrokePoint> pts = [];
        for (int i = 0; i <= 5; i++) {
          final double a = (i / 5) * 2 * pi - pi / 2;
          pts.add(
            MathsPadStrokePoint(center + Offset(cos(a) * radiusX, sin(a) * radiusY)),
          );
        }
        createdLines.add(
          MathsPadLine(
            points: pts,
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        break;

      case BasicShapeType.hexagon:
        final List<MathsPadStrokePoint> pts = [];
        for (int i = 0; i <= 6; i++) {
          final double a = (i / 6) * 2 * pi;
          pts.add(
            MathsPadStrokePoint(center + Offset(cos(a) * radiusX, sin(a) * radiusY)),
          );
        }
        createdLines.add(
          MathsPadLine(
            points: pts,
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        break;

      case BasicShapeType.diamond:
        final pts = [
          MathsPadStrokePoint(Offset(center.dx, rect.top)),
          MathsPadStrokePoint(Offset(rect.right, center.dy)),
          MathsPadStrokePoint(Offset(center.dx, rect.bottom)),
          MathsPadStrokePoint(Offset(rect.left, center.dy)),
          MathsPadStrokePoint(Offset(center.dx, rect.top)),
        ];
        createdLines.add(
          MathsPadLine(
            points: pts,
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        break;

      case BasicShapeType.star:
        final List<MathsPadStrokePoint> pts = [];
        for (int i = 0; i < 10; i++) {
          final double rx = i.isEven ? radiusX : radiusX * 0.45;
          final double ry = i.isEven ? radiusY : radiusY * 0.45;
          final double a = (i / 10) * 2 * pi - pi / 2;
          pts.add(MathsPadStrokePoint(center + Offset(cos(a) * rx, sin(a) * ry)));
        }
        pts.add(pts.first);
        createdLines.add(
          MathsPadLine(
            points: pts,
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        break;

      case BasicShapeType.coordinateAxes:
        // X-Axis with Arrowhead
        createdLines.add(
          MathsPadLine(
            points: [
              MathsPadStrokePoint(Offset(rect.left, center.dy)),
              MathsPadStrokePoint(Offset(rect.right, center.dy)),
            ],
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        createdLines.add(
          MathsPadLine(
            points: [
              MathsPadStrokePoint(Offset(rect.right - 12, center.dy - 8)),
              MathsPadStrokePoint(Offset(rect.right, center.dy)),
              MathsPadStrokePoint(Offset(rect.right - 12, center.dy + 8)),
            ],
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );

        // Y-Axis with Arrowhead
        createdLines.add(
          MathsPadLine(
            points: [
              MathsPadStrokePoint(Offset(center.dx, rect.bottom)),
              MathsPadStrokePoint(Offset(center.dx, rect.top)),
            ],
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        createdLines.add(
          MathsPadLine(
            points: [
              MathsPadStrokePoint(Offset(center.dx - 8, rect.top + 12)),
              MathsPadStrokePoint(Offset(center.dx, rect.top)),
              MathsPadStrokePoint(Offset(center.dx + 8, rect.top + 12)),
            ],
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        break;

      case BasicShapeType.arrowHorizontal:
        createdLines.add(
          MathsPadLine(
            points: [
              MathsPadStrokePoint(Offset(rect.left, center.dy)),
              MathsPadStrokePoint(Offset(rect.right, center.dy)),
            ],
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        createdLines.add(
          MathsPadLine(
            points: [
              MathsPadStrokePoint(Offset(rect.right - 14, center.dy - 10)),
              MathsPadStrokePoint(Offset(rect.right, center.dy)),
              MathsPadStrokePoint(Offset(rect.right - 14, center.dy + 10)),
            ],
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        break;

      case BasicShapeType.arrowVertical:
        createdLines.add(
          MathsPadLine(
            points: [
              MathsPadStrokePoint(Offset(center.dx, rect.bottom)),
              MathsPadStrokePoint(Offset(center.dx, rect.top)),
            ],
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        createdLines.add(
          MathsPadLine(
            points: [
              MathsPadStrokePoint(Offset(center.dx - 10, rect.top + 14)),
              MathsPadStrokePoint(Offset(center.dx, rect.top)),
              MathsPadStrokePoint(Offset(center.dx + 10, rect.top + 14)),
            ],
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        break;

      case BasicShapeType.cube3d:
        final Offset off = Offset(rect.width * 0.25, -rect.height * 0.25);
        final Rect frontRect = Rect.fromLTWH(
          rect.left,
          rect.top + rect.height * 0.25,
          rect.width * 0.75,
          rect.height * 0.75,
        );
        final Rect backRect = frontRect.shift(off);

        // Front Face
        createdLines.add(
          MathsPadLine(
            points: [
              MathsPadStrokePoint(frontRect.topLeft),
              MathsPadStrokePoint(frontRect.topRight),
              MathsPadStrokePoint(frontRect.bottomRight),
              MathsPadStrokePoint(frontRect.bottomLeft),
              MathsPadStrokePoint(frontRect.topLeft),
            ],
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );

        // Back Face
        createdLines.add(
          MathsPadLine(
            points: [
              MathsPadStrokePoint(backRect.topLeft),
              MathsPadStrokePoint(backRect.topRight),
              MathsPadStrokePoint(backRect.bottomRight),
              MathsPadStrokePoint(backRect.bottomLeft),
              MathsPadStrokePoint(backRect.topLeft),
            ],
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );

        // 4 Connecting Edges
        createdLines.add(
          MathsPadLine(
            points: [
              MathsPadStrokePoint(frontRect.topLeft),
              MathsPadStrokePoint(backRect.topLeft),
            ],
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        createdLines.add(
          MathsPadLine(
            points: [
              MathsPadStrokePoint(frontRect.topRight),
              MathsPadStrokePoint(backRect.topRight),
            ],
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        createdLines.add(
          MathsPadLine(
            points: [
              MathsPadStrokePoint(frontRect.bottomRight),
              MathsPadStrokePoint(backRect.bottomRight),
            ],
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        createdLines.add(
          MathsPadLine(
            points: [
              MathsPadStrokePoint(frontRect.bottomLeft),
              MathsPadStrokePoint(backRect.bottomLeft),
            ],
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        break;
    }

    return createdLines;
  }

  // Insert geometric shapes & mathematical diagrams into active canvas
  void _insertBasicShape(BasicShapeType shapeType) {
    setState(() {
      _activeShapeTool = shapeType;
      _toolMode = CanvasToolMode.pen; // Enforce drawing mode for active shape
      _selectedLines.clear();
    });
  }

  void _resetView() {
    _frictionController?.stop();
    setState(() {
      _panOffset = Offset.zero;
      _scale = 1.0;
      _panNotifier.value = Offset.zero;
      _scaleNotifier.value = 1.0;
    });
  }

  void _zoomIn() {
    _frictionController?.stop();
    setState(() {
      _scale = (_scale * 1.2).clamp(0.25, 4.0);
      _scaleNotifier.value = _scale;
    });
  }

  void _zoomOut() {
    _frictionController?.stop();
    setState(() {
      _scale = (_scale / 1.2).clamp(0.25, 4.0);
      _scaleNotifier.value = _scale;
    });
  }

  void _undo() {
    if (_lines.isNotEmpty) {
      setState(() {
        final removed = _lines.removeLast();
        _undoHistory.add(removed);
        _selectedLines.clear();
        _removeOrphanedAngleLabels([removed]);
      });
      _finishedStrokesNotifier.value++;
    }
  }

  void _redo() {
    if (_undoHistory.isNotEmpty) {
      final restored = _undoHistory.removeLast();
      _buildAndCachePath(restored);
      setState(() {
        _lines.add(restored);
        _selectedLines.clear();
      });
      _finishedStrokesNotifier.value++;
    }
  }

  void _clearCanvas() {
    setState(() {
      _lines.clear();
      _undoHistory.clear();
      _selectedLines.clear();
      _lassoPoints.clear();
      _fixedAngleLabels.clear();
      _textLabels.clear();
      _textEditorController?.dispose();
      _textEditorController = null;
      _textEditorOpen = false;
      _textEditingIndex = null;
      _textEditorWorldPos = null;
    });
    _finishedStrokesNotifier.value++;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final bgColor = widget.isTransparentBg
        ? Colors.transparent
        : (_bgMode == CanvasBgMode.jyamitiCosmos
              ? const Color(0xFF0F2B52)
              : (isDark ? const Color(0xFF0F172A) : const Color(0xFFFCFDFE)));

    return Focus(
      focusNode: _canvasFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final ctrl = HardwareKeyboard.instance.isControlPressed;
          if (ctrl && event.logicalKey == LogicalKeyboardKey.keyC) {
            _copySelectedLines();
            return KeyEventResult.handled;
          }
          if (ctrl && event.logicalKey == LogicalKeyboardKey.keyV) {
            _pasteClipboard();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: widget.isTransparentBg
              ? BorderRadius.zero
              : BorderRadius.circular(20),
          border: widget.isTransparentBg
              ? null
              : Border.all(
                  color: const Color(0xFF6366F1).withOpacity(0.3),
                  width: 1.5,
                ),
          boxShadow: widget.isTransparentBg
              ? null
              : [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withOpacity(0.12),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
        ),
        child: Column(
          children: [
            // Whiteboard Header Controls Toolbar
            _buildToolbar(context, isDark),

            // Infinite Writing Canvas Body
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Track the canvas's own size (excluding the toolbar
                  // above it) so newly-added instruments can be centered
                  // in the actually-visible canvas area.
                  _canvasSize = constraints.biggest;
                  return _buildCanvasStack(context, isDark, bgColor);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCanvasStack(BuildContext context, bool isDark, Color bgColor) {
    return ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(18),
                ),
                child: Stack(
                  children: [
                    Listener(
                      onPointerDown: _onPointerDown,
                      onPointerMove: _onPointerMove,
                      onPointerUp: _onPointerUp,
                      onPointerCancel: _onPointerCancel,
                      onPointerSignal: _onPointerSignal,
                      onPointerHover: _onPointerHover,
                      child: GestureDetector(
                        onScaleStart: _onScaleStart,
                        onScaleUpdate: _onScaleUpdate,
                        onScaleEnd: _onScaleEnd,
                        // ValueListenableBuilder Dual-Layer Stack:
                        // Layer 1 (Finished Strokes): Repaints ONLY when _lines updates (0 repaints during live drag)
                        // Layer 2 (Active Drawing): Repaints live stroke overlay at 120 FPS
                        child: ValueListenableBuilder<Offset>(
                          valueListenable: _panNotifier,
                          builder: (_, pan, child) {
                            return ValueListenableBuilder<double>(
                              valueListenable: _scaleNotifier,
                              builder: (_, sc, child) {
                                return Stack(
                                  children: [
                                    // Layer 1: Finished Strokes & Background
                                    ValueListenableBuilder<int>(
                                      valueListenable: _finishedStrokesNotifier,
                                      builder: (_, _, child) {
                                        return RepaintBoundary(
                                          child: CustomPaint(
                                            size: Size.infinite,
                                            painter: _MathsPadFinishedStrokesPainter(
                                              lines: _lines,
                                              bgMode: _bgMode,
                                              isDark: isDark,
                                              canvasBgColor: bgColor,
                                              panOffset: pan,
                                              scale: sc,
                                            ),
                                          ),
                                        );
                                      },
                                    ),

                                    // Layer 2: Active Drawing Overlay & Handles
                                    ValueListenableBuilder<int>(
                                      valueListenable: _activeDrawingNotifier,
                                      builder: (_, _, child) {
                                        return RepaintBoundary(
                                          child: CustomPaint(
                                            size: Size.infinite,
                                            painter:
                                                _MathsPadActiveOverlayPainter(
                                                  currentLine: _currentLine,
                                                  selectedLines: _selectedLines,
                                                  lassoPoints: _lassoPoints,
                                                  panOffset: pan,
                                                  scale: sc,
                                                  activeShapeTool:
                                                      _activeShapeTool,
                                                  shapeDragStartPos:
                                                      _shapeDragStartPos,
                                                  shapeDragCurrentPos:
                                                      _shapeDragCurrentPos,
                                                  selectedColor: _selectedColor,
                                                  penWidth: _penWidth,
                                                  isDark: isDark,
                                                ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),

                    // Geometry Instruments Overlay (Ruler/Protractor/Compass/Set Squares).
                    // Lives inside the same pan/zoom transform as the canvas layers above,
                    // so instruments stay attached to the drawing plane as the user
                    // pans/zooms. Each instrument widget manages its own small handle
                    // GestureDetectors; empty overlay space falls through to the
                    // drawing Listener/GestureDetector beneath it.
                    IgnorePointer(
                      ignoring:
                          _instruments.isEmpty &&
                          _textLabels.isEmpty &&
                          !_textEditorOpen,
                      child: ValueListenableBuilder<Offset>(
                        valueListenable: _panNotifier,
                        builder: (_, pan, child) {
                          return ValueListenableBuilder<double>(
                            valueListenable: _scaleNotifier,
                            builder: (_, sc, child) {
                              return Transform(
                                transform: Matrix4.identity()
                                  ..translate(pan.dx, pan.dy)
                                  ..scale(sc),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    ..._instruments.map(_buildInstrumentWidget),
                                    IgnorePointer(
                                      child: CustomPaint(
                                        size: Size.infinite,
                                        painter: _AngleArcPainter(_currentAngleArcs()),
                                      ),
                                    ),
                                    ..._fixedAngleLabels.map(
                                      (l) => _buildAngleBadge(
                                        l.labelPosition,
                                        l.text,
                                        live: false,
                                      ),
                                    ),
                                    if (_toolMode == CanvasToolMode.angle &&
                                        _angleWaitingForSecondLine &&
                                        _angleVertex != null &&
                                        _angleOtherEndOfA != null &&
                                        _angleLiveEnd != null &&
                                        _angleLiveDegrees != null)
                                      _buildAngleBadge(
                                        _bisectorPoint(
                                          _angleVertex!,
                                          (_angleOtherEndOfA! - _angleVertex!).direction,
                                          _signedAngleDiff(
                                            (_angleOtherEndOfA! - _angleVertex!).direction,
                                            (_angleLiveEnd! - _angleVertex!).direction,
                                          ),
                                        ),
                                        '${_angleLiveDegrees!.toStringAsFixed(1)}°',
                                        live: true,
                                      ),
                                    if (_toolMode ==
                                            CanvasToolMode.polygonAngle &&
                                        _polygonVertices.length >= 2 &&
                                        _polygonLiveEnd != null &&
                                        _polygonLiveDegrees != null)
                                      _buildAngleBadge(
                                        _bisectorPoint(
                                          _polygonVertices.last,
                                          (_polygonVertices[_polygonVertices.length - 2] -
                                                  _polygonVertices.last)
                                              .direction,
                                          _signedAngleDiff(
                                            (_polygonVertices[_polygonVertices.length - 2] -
                                                    _polygonVertices.last)
                                                .direction,
                                            (_polygonLiveEnd! - _polygonVertices.last)
                                                .direction,
                                          ),
                                        ),
                                        '${_polygonLiveDegrees!.toStringAsFixed(1)}°',
                                        live: true,
                                      ),
                                    if (_toolMode ==
                                            CanvasToolMode.circleArc &&
                                        _circleCenter != null &&
                                        _circleLiveEnd != null &&
                                        !_circleHasStartedSweeping)
                                      _buildAngleBadge(
                                        _perpendicularMidpoint(
                                          _circleCenter!,
                                          _circleLiveEnd!,
                                          20,
                                        ),
                                        '${((_circleLiveEnd! - _circleCenter!).distance / kPxPerCm).toStringAsFixed(1)} cm',
                                        live: true,
                                      ),
                                    if (_toolMode ==
                                            CanvasToolMode.straightLine &&
                                        _currentLine != null &&
                                        _straightLineLiveEnd != null)
                                      _buildAngleBadge(
                                        _perpendicularMidpoint(
                                          _currentLine!.points.first.offset,
                                          _straightLineLiveEnd!,
                                          20,
                                        ),
                                        '${((_straightLineLiveEnd! - _currentLine!.points.first.offset).distance / kPxPerCm).toStringAsFixed(1)} cm',
                                        live: true,
                                      ),
                                    if (_toolMode == CanvasToolMode.spacer &&
                                        _spacerDrag != null)
                                      _buildAngleBadge(
                                        _spacerDrag!.isVertical
                                            ? _spacerDrag!.startWorld +
                                                  Offset(
                                                    24,
                                                    _spacerLiveShift / 2,
                                                  )
                                            : _spacerDrag!.startWorld +
                                                  Offset(
                                                    _spacerLiveShift / 2,
                                                    24,
                                                  ),
                                        '${(_spacerLiveShift / kPxPerCm).toStringAsFixed(1)} cm',
                                        live: true,
                                      ),
                                    ..._textLabels.asMap().entries.map(
                                      (e) => _buildTextLabelWidget(e.key, e.value),
                                    ),
                                    _buildTextEditorOverlay(isDark),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),

                    // Top Question Banner Card overlay for Tutors (ONLY visible in Full Screen mode when questionText is provided)
                    Builder(
                      builder: (context) {
                        if (!widget.isFullScreen) return const SizedBox();
                        if (widget.questionText == null ||
                            widget.questionText!.trim().isEmpty) {
                          return const SizedBox();
                        }

                        final String effectiveQText = widget.questionText!
                            .trim();

                        return Positioned(
                          top: 10,
                          left: 16,
                          right: 16,
                          child: Center(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              constraints: const BoxConstraints(maxWidth: 800),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    (isDark
                                            ? const Color(0xFF1E293B)
                                            : Colors.white)
                                        .withOpacity(0.95),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(
                                    0xFF6366F1,
                                  ).withOpacity(0.5),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFF6366F1,
                                          ).withOpacity(0.18),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.quiz_rounded,
                                              size: 14,
                                              color: Color(0xFF6366F1),
                                            ),
                                            SizedBox(width: 4),
                                            Text(
                                              'Question',
                                              style: TextStyle(
                                                color: Color(0xFF6366F1),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Spacer(),
                                      InkWell(
                                        onTap: () => setState(
                                          () => _isQuestionBannerExpanded =
                                              !_isQuestionBannerExpanded,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Padding(
                                          padding: const EdgeInsets.all(2.0),
                                          child: Icon(
                                            _isQuestionBannerExpanded
                                                ? Icons
                                                      .keyboard_arrow_up_rounded
                                                : Icons
                                                      .keyboard_arrow_down_rounded,
                                            size: 20,
                                            color: context.textColor60,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_isQuestionBannerExpanded) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      effectiveQText,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: context.textColor,
                                        height: 1.35,
                                      ),
                                      maxLines: 4,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    // Floating Active Stylus Barrel Eraser Alert
                    if (_isStylusBarrelPressed)
                      Positioned(
                        top: 12,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade700,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.amber.withOpacity(0.4),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.cleaning_services_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Stylus Pen Button Pressed → ERASER ACTIVE',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // Floating Action Bar for Selected Items (Move, Duplicate, Delete)
                    if (_selectedLines.isNotEmpty)
                      Positioned(
                        bottom: 16,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF1E293B)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(25),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.25),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                              border: Border.all(
                                color: const Color(0xFF6366F1).withOpacity(0.5),
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.touch_app_rounded,
                                  size: 16,
                                  color: Color(0xFF6366F1),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${_selectedLines.length} selected • Drag box to move',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: context.textColor,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                // Copy button (Ctrl+C)
                                ElevatedButton.icon(
                                  onPressed: _copySelectedLines,
                                  icon: const Icon(
                                    Icons.content_copy_rounded,
                                    size: 15,
                                    color: Colors.white,
                                  ),
                                  label: const Text(
                                    'Copy',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0EA5E9),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // Duplicate button
                                ElevatedButton.icon(
                                  onPressed: _duplicateSelectedLines,
                                  icon: const Icon(
                                    Icons.copy_rounded,
                                    size: 15,
                                    color: Colors.white,
                                  ),
                                  label: const Text(
                                    'Duplicate',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF6366F1),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                ElevatedButton.icon(
                                  onPressed: _deleteSelectedLines,
                                  icon: const Icon(
                                    Icons.delete_forever_rounded,
                                    size: 15,
                                    color: Colors.white,
                                  ),
                                  label: const Text(
                                    'Delete',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.redAccent,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                  ),
                                  onPressed: () =>
                                      setState(() => _selectedLines.clear()),
                                  tooltip: 'Deselect',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // Floating Tool Hint Pill
                    if (_selectedLines.isEmpty && !_isStylusBarrelPressed)
                      Positioned(
                        bottom: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: (isDark ? Colors.black : Colors.white)
                                .withOpacity(0.75),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: (isDark ? Colors.white : Colors.black)
                                  .withOpacity(0.1),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset(
                                'assets/image/logo.png',
                                height: 20,
                                width: 20,
                              ),
                              Icon(
                                _toolMode == CanvasToolMode.eraser
                                    ? (_eraserMode == EraserMode.stroke
                                          ? Icons.auto_fix_high_rounded
                                          : Icons.cleaning_services_rounded)
                                    : (_toolMode == CanvasToolMode.tapSelect
                                          ? Icons.touch_app_rounded
                                          : (_toolMode == CanvasToolMode.lasso
                                                ? Icons.gesture_rounded
                                                : (_toolMode ==
                                                          CanvasToolMode.pan
                                                      ? Icons.back_hand_rounded
                                                      : Icons.edit_rounded))),
                                size: 14,
                                color: context.textColor70,
                              ),
                              const SizedBox(width: 4),
                              ValueListenableBuilder<double>(
                                valueListenable: _scaleNotifier,
                                builder: (_, sc, _c) {
                                  return Text(
                                    _toolMode == CanvasToolMode.eraser
                                        ? (_eraserMode == EraserMode.stroke
                                              ? 'Stroke Eraser • Tap any stroke to erase whole line'
                                              : 'Area Eraser • Drag to erase points')
                                        : (_toolMode == CanvasToolMode.tapSelect
                                              ? 'Tap any line to select & move/duplicate'
                                              : (_toolMode ==
                                                        CanvasToolMode.lasso
                                                    ? 'Draw loop around items to select & move/duplicate'
                                                    : 'Infinite Canvas • ${(sc * 100).round()}%')),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: context.textColor70,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }

  Widget _buildToolbar(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        border: Border(
          bottom: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Pen, Stroke Eraser, Tap-to-Select, Lasso Select, & Pan Tool
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  _buildIconButton(
                    icon: Icons.edit_rounded,
                    tooltip: 'Pen Mode',
                    isSelected:
                        _toolMode == CanvasToolMode.pen &&
                        _activeShapeTool == null,
                    onTap: () => setState(() {
                      _toolMode = CanvasToolMode.pen;
                      _activeShapeTool = null;
                      _selectedWidth = _penWidth;
                      _selectedLines.clear();
                    }),
                  ),
                  _buildIconButton(
                    icon: _lineAxisLocked
                        ? Icons.add_rounded
                        : Icons.horizontal_rule_rounded,
                    tooltip: _lineAxisLocked
                        ? 'Straight Line Tool: HORIZONTAL/VERTICAL ONLY -- '
                              'length shown live; starting/ending near '
                              "another line's tip connects to it exactly "
                              '(tap icon again to allow any angle)'
                        : 'Straight Line Tool: drag to draw a line with its '
                              "length shown live; starting/ending near "
                              "another line's tip connects to it exactly "
                              '(tap icon again to lock to horizontal/vertical only)',
                    isSelected: _toolMode == CanvasToolMode.straightLine,
                    onTap: () => setState(() {
                      if (_toolMode == CanvasToolMode.straightLine) {
                        _lineAxisLocked = !_lineAxisLocked;
                      } else {
                        _toolMode = CanvasToolMode.straightLine;
                      }
                      _activeShapeTool = null;
                      _selectedWidth = _penWidth;
                      _selectedLines.clear();
                    }),
                  ),
                  _buildIconButton(
                    icon: Icons.call_split_rounded,
                    tooltip:
                        'Angle Tool: draw a line, then drag a second line '
                        'from either of its ends to see the angle between '
                        'them live -- release to fix it',
                    isSelected: _toolMode == CanvasToolMode.angle,
                    onTap: () => setState(() {
                      _toolMode = CanvasToolMode.angle;
                      _activeShapeTool = null;
                      _selectedWidth = _penWidth;
                      _selectedLines.clear();
                      _resetAngleTool();
                    }),
                  ),
                  _buildIconButton(
                    icon: Icons.timeline_rounded,
                    tooltip:
                        'Polygon Angle Tool: draw connected segments -- each '
                        'one continues from the last point and shows the '
                        'angle at that corner live; end back near the start '
                        'to close the shape',
                    isSelected: _toolMode == CanvasToolMode.polygonAngle,
                    onTap: () => setState(() {
                      _toolMode = CanvasToolMode.polygonAngle;
                      _activeShapeTool = null;
                      _selectedWidth = _penWidth;
                      _selectedLines.clear();
                      _resetPolygonTool();
                    }),
                  ),
                  _buildIconButton(
                    icon: Icons.blur_circular_rounded,
                    tooltip:
                        'Circle/Arc Tool: drag out to set the radius, then '
                        'keep dragging in a curve around that same point -- '
                        'only the traced arc/circle stays when you release',
                    isSelected: _toolMode == CanvasToolMode.circleArc,
                    onTap: () => setState(() {
                      _toolMode = CanvasToolMode.circleArc;
                      _activeShapeTool = null;
                      _selectedWidth = _penWidth;
                      _selectedLines.clear();
                      _resetCircleArcTool();
                    }),
                  ),
                  _buildIconButton(
                    icon: Icons.format_color_fill_rounded,
                    tooltip:
                        'Fill Tool: tap inside any closed area to flood-fill '
                        'it with the current color, like a paint bucket',
                    isSelected: _toolMode == CanvasToolMode.fill,
                    onTap: () => setState(() {
                      _toolMode = CanvasToolMode.fill;
                      _activeShapeTool = null;
                      _selectedLines.clear();
                    }),
                  ),
                  _buildIconButton(
                    icon: Icons.text_fields_rounded,
                    tooltip:
                        'Text Label: tap empty space to add a label; tap an '
                        'existing one to edit it, or drag it to move it',
                    isSelected: _toolMode == CanvasToolMode.text,
                    onTap: () => setState(() {
                      _toolMode = CanvasToolMode.text;
                      _activeShapeTool = null;
                      _selectedLines.clear();
                    }),
                  ),
                  _buildIconButton(
                    icon: _spacerHorizontalOnly
                        ? Icons.compare_arrows_rounded
                        : Icons.unfold_more_rounded,
                    tooltip: _spacerHorizontalOnly
                        ? 'Spacer Tool: HORIZONTAL ONLY -- drag through a gap '
                              'to push everything past that point sideways '
                              '(tap icon again to go back to any direction)'
                        : 'Spacer Tool: drag through a gap to push everything '
                              'past that point further away, live, opening up '
                              'blank space to work in (tap icon again for '
                              'horizontal-only)',
                    isSelected: _toolMode == CanvasToolMode.spacer,
                    onTap: () => setState(() {
                      if (_toolMode == CanvasToolMode.spacer) {
                        _spacerHorizontalOnly = !_spacerHorizontalOnly;
                      } else {
                        _toolMode = CanvasToolMode.spacer;
                      }
                      _activeShapeTool = null;
                      _selectedLines.clear();
                    }),
                  ),
                  _buildIconButton(
                    icon: _eraserMode == EraserMode.stroke
                        ? Icons.auto_fix_high_rounded
                        : Icons.cleaning_services_rounded,
                    tooltip: _eraserMode == EraserMode.stroke
                        ? 'Stroke Eraser: ACTIVE (Tap stroke to erase line • Double-click/Tap icon to switch to Area Eraser)'
                        : 'Area Eraser: ACTIVE (Double-click/Tap icon to switch to Stroke Eraser)',
                    isSelected: _toolMode == CanvasToolMode.eraser,
                    onTap: () {
                      _activeShapeTool = null;
                      _handleEraserButtonTap();
                    },
                  ),
                  _buildIconButton(
                    icon: Icons.touch_app_rounded,
                    tooltip: 'Tap Line to Select, Move & Duplicate',
                    isSelected: _toolMode == CanvasToolMode.tapSelect,
                    onTap: () => setState(() {
                      _toolMode = CanvasToolMode.tapSelect;
                      _activeShapeTool = null;
                    }),
                  ),
                  _buildIconButton(
                    icon: Icons.gesture_rounded,
                    tooltip: 'Lasso Select, Move & Duplicate Area',
                    isSelected: _toolMode == CanvasToolMode.lasso,
                    onTap: () => setState(() {
                      _toolMode = CanvasToolMode.lasso;
                      _activeShapeTool = null;
                      _selectedLines.clear();
                    }),
                  ),
                  _buildIconButton(
                    icon: Icons.back_hand_rounded,
                    tooltip: 'Pan Canvas (Hand Tool)',
                    isSelected: _toolMode == CanvasToolMode.pan,
                    onTap: () => setState(() {
                      _toolMode = CanvasToolMode.pan;
                      _activeShapeTool = null;
                      _selectedLines.clear();
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Geometry Instruments: Ruler, Protractor, Compass, Set Squares
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  _buildIconButton(
                    icon: Icons.straighten_rounded,
                    tooltip: 'Add Ruler',
                    onTap: () => _addInstrument(
                      (i) => i is RulerState,
                      (center) => RulerState(pivot: center),
                    ),
                  ),
                  _buildIconButton(
                    icon: Icons.architecture_rounded,
                    tooltip: 'Add Protractor',
                    onTap: () => _addInstrument(
                      (i) => i is ProtractorState,
                      (center) => ProtractorState(pivot: center),
                    ),
                  ),
                  _buildIconButton(
                    icon: Icons.radio_button_unchecked_rounded,
                    tooltip: 'Add Compass',
                    onTap: () => _addInstrument(
                      (i) => i is CompassState,
                      (center) => CompassState(pivot: center),
                    ),
                  ),
                  _buildIconButton(
                    icon: Icons.change_history_rounded,
                    tooltip: 'Add Set Square (45-45-90)',
                    onTap: () => _addInstrument(
                      (i) => i is SetSquareState && i.kind == SetSquareKind.fortyFive,
                      (center) => SetSquareState(
                        pivot: center,
                        kind: SetSquareKind.fortyFive,
                      ),
                    ),
                  ),
                  _buildIconButton(
                    icon: Icons.change_history_outlined,
                    tooltip: 'Add Set Square (30-60-90)',
                    onTap: () => _addInstrument(
                      (i) => i is SetSquareState && i.kind == SetSquareKind.thirtySixty,
                      (center) => SetSquareState(
                        pivot: center,
                        kind: SetSquareKind.thirtySixty,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Color Palette
            Row(
              children: _palette.map((color) {
                final isSelected =
                    _toolMode == CanvasToolMode.pen &&
                    _activeShapeTool == null &&
                    _selectedColor.value == color.value;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedColor = color;
                      _toolMode = CanvasToolMode.pen;
                      _activeShapeTool = null;
                      _selectedWidth = _penWidth;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF6366F1)
                            : Colors.grey.withOpacity(0.4),
                        width: isSelected ? 3 : 1,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: color.withOpacity(0.6),
                                blurRadius: 6,
                              ),
                            ]
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(width: 10),

            // Stroke Width Selector
            PopupMenuButton<double>(
              tooltip: 'Stroke Thickness',
              icon: Row(
                children: [
                  Icon(
                    Icons.line_weight_rounded,
                    size: 18,
                    color: context.textColor,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '${_selectedWidth.toInt()}px',
                    style: TextStyle(fontSize: 11, color: context.textColor),
                  ),
                ],
              ),
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              onSelected: (w) => setState(() {
                _selectedWidth = w;
                if (_toolMode == CanvasToolMode.eraser) {
                  _eraserWidth = w;
                } else {
                  _penWidth = w;
                }
              }),
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: 2.0, child: Text('Fine (2px)')),
                const PopupMenuItem(value: 4.0, child: Text('Medium (4px)')),
                const PopupMenuItem(value: 8.0, child: Text('Thick (8px)')),
                const PopupMenuItem(value: 14.0, child: Text('Marker (14px)')),
              ],
            ),

            const SizedBox(width: 6),

            // Basic Shapes & Diagrams Dropdown (Horizontal Ribbon Palette)
            PopupMenuButton<void>(
              tooltip: 'Select Shape to Draw',
              offset: const Offset(0, 36),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              icon: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: _activeShapeTool != null
                      ? const Color(0xFF6366F1).withOpacity(0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.category_rounded,
                      size: 18,
                      color: _activeShapeTool != null
                          ? const Color(0xFF6366F1)
                          : context.textColor,
                    ),
                    Icon(
                      Icons.arrow_drop_down_rounded,
                      size: 16,
                      color: _activeShapeTool != null
                          ? const Color(0xFF6366F1)
                          : context.textColor,
                    ),
                  ],
                ),
              ),
              itemBuilder: (ctx) => [
                PopupMenuItem<void>(
                  enabled: false,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _shapeTools.map((item) {
                        final isSelected = _activeShapeTool == item.type;
                        return Tooltip(
                          message: item.tooltip,
                          child: InkWell(
                            onTap: () {
                              Navigator.pop(ctx);
                              _insertBasicShape(item.type);
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF6366F1).withOpacity(0.25)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: isSelected
                                    ? Border.all(
                                        color: const Color(0xFF6366F1),
                                        width: 1.5,
                                      )
                                    : null,
                              ),
                              child: Icon(
                                item.icon,
                                size: 19,
                                color: isSelected
                                    ? const Color(0xFF6366F1)
                                    : context.textColor,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(width: 6),

            // Paper Background Mode Toggle
            PopupMenuButton<CanvasBgMode>(
              tooltip: 'Background Pattern',
              icon: Row(
                children: [
                  Icon(
                    _bgMode == CanvasBgMode.grid
                        ? Icons.grid_on_rounded
                        : (_bgMode == CanvasBgMode.ruled
                              ? Icons.notes_rounded
                              : Icons.crop_portrait_rounded),
                    size: 18,
                    color: context.textColor,
                  ),
                ],
              ),
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              onSelected: (m) => setState(() => _bgMode = m),
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: CanvasBgMode.grid,
                  child: Text('📐 Math Grid'),
                ),
                const PopupMenuItem(
                  value: CanvasBgMode.ruled,
                  child: Text('📝 Ruled Lines'),
                ),
                const PopupMenuItem(
                  value: CanvasBgMode.blank,
                  child: Text('📄 Blank Canvas'),
                ),
                const PopupMenuItem(
                  value: CanvasBgMode.jyamitiCosmos,
                  child: Text('🌌 Jyamiti Cosmos (#0F2B52)'),
                ),
              ],
            ),

            const SizedBox(width: 10),

            // Zoom Controls
            _buildIconButton(
              icon: Icons.zoom_out_rounded,
              tooltip: 'Zoom Out',
              onTap: _zoomOut,
            ),
            Tooltip(
              message: 'Reset Center & 100% Zoom',
              child: InkWell(
                onTap: _resetView,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: ValueListenableBuilder<double>(
                    valueListenable: _scaleNotifier,
                    builder: (_, sc, _c) => Text(
                      '${(sc * 100).round()}%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: context.textColor70,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _buildIconButton(
              icon: Icons.zoom_in_rounded,
              tooltip: 'Zoom In',
              onTap: _zoomIn,
            ),

            const SizedBox(width: 10),

            // Full Screen Toggle Button
            if (widget.onToggleFullScreen != null) ...[
              _buildIconButton(
                icon: widget.isFullScreen
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                tooltip: widget.isFullScreen
                    ? 'Exit Full Screen'
                    : 'Full Screen Whiteboard',
                isSelected: widget.isFullScreen,
                onTap: widget.onToggleFullScreen!,
              ),
              const SizedBox(width: 4),
            ],

            // Undo / Redo / Clear
            _buildIconButton(
              icon: Icons.undo_rounded,
              tooltip: 'Undo',
              isDisabled: _lines.isEmpty,
              onTap: _undo,
            ),
            _buildIconButton(
              icon: Icons.redo_rounded,
              tooltip: 'Redo',
              isDisabled: _undoHistory.isEmpty,
              onTap: _redo,
            ),
            _buildIconButton(
              icon: Icons.delete_outline_rounded,
              tooltip: 'Clear Canvas',
              color: Colors.redAccent,
              onTap: _clearCanvas,
            ),

            if (widget.enableSaveNotes) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: 'Save Note to My Notes',
                child: InkWell(
                  onTap: _saveNote,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF10B981),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.save_rounded,
                          size: 15,
                          color: Color(0xFF10B981),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'Save Note',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],

            // Paste Button – visible ONLY when clipboard has copied strokes
            if (_clipboard.isNotEmpty) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: 'Paste Copied Strokes (Ctrl+V)',
                child: InkWell(
                  onTap: _pasteClipboard,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0EA5E9).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF0EA5E9),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.content_paste_rounded,
                          size: 15,
                          color: Color(0xFF0EA5E9),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'Paste',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0EA5E9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],

            if (widget.onClose != null) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: widget.onClose,
                tooltip: 'Close Writing Screen',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool isSelected = false,
    bool isDisabled = false,
    Color? color,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: isDisabled ? null : onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF6366F1).withOpacity(0.25)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: isDisabled
                ? Colors.grey.withOpacity(0.3)
                : (isSelected
                      ? const Color(0xFF6366F1)
                      : (color ?? context.textColor)),
          ),
        ),
      ),
    );
  }

  Future<void> _saveNote() async {
    final titleController = TextEditingController(text: widget.noteTitle ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          title: Text(
            widget.noteId != null
                ? 'Update Saved Note'
                : 'Save Note to My Notes',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter a label for this note:',
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: titleController,
                autofocus: true,
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  labelText: 'Note Label',
                  labelStyle: TextStyle(
                    color: isDark ? Colors.white60 : Colors.black,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: isDark ? Colors.white70 : Colors.black26,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(
                      color: Color(0xFF6366F1),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                if (titleController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Please enter a note label')),
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Save',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      final label = titleController.text.trim();
      final prefs = await SharedPreferences.getInstance();
      final savedNotesStr = prefs.getString('jyamiti_my_notes') ?? '[]';
      final List<dynamic> savedNotes = jsonDecode(savedNotesStr);

      final serializedLines = _lines.map(_lineToJson).toList();
      final noteId =
          widget.noteId ?? DateTime.now().millisecondsSinceEpoch.toString();
      final newNote = {
        'id': noteId,
        'title': label,
        'timestamp': DateTime.now().toIso8601String(),
        'lines': serializedLines,
      };

      if (widget.noteId != null) {
        final index = savedNotes.indexWhere((n) => n['id'] == widget.noteId);
        if (index != -1) {
          savedNotes[index] = newNote;
        } else {
          savedNotes.add(newNote);
        }
      } else {
        savedNotes.add(newNote);
      }

      await prefs.setString('jyamiti_my_notes', jsonEncode(savedNotes));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Note "$label" saved successfully!'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    }
  }

  Map<String, dynamic> _lineToJson(MathsPadLine line) {
    return {
      'points': line.points
          .map((p) => {'dx': p.offset.dx, 'dy': p.offset.dy})
          .toList(),
      'color': line.color.value,
      'strokeWidth': line.strokeWidth,
      'isEraser': line.isEraser,
      'isShape': line.isShape,
    };
  }
}

// ── Top-Level Helper Utilities for High Performance Curve Smoothing ─────────────
List<Offset> _chaikinSmooth(List<Offset> pts, {int iterations = 3}) {
  if (pts.length < 3) return pts;

  List<Offset> filtered = [pts.first];
  for (int i = 1; i < pts.length - 1; i++) {
    final prev = pts[i - 1];
    final curr = pts[i];
    final next = pts[i + 1];
    filtered.add(
      Offset(
        0.20 * prev.dx + 0.60 * curr.dx + 0.20 * next.dx,
        0.20 * prev.dy + 0.60 * curr.dy + 0.20 * next.dy,
      ),
    );
  }
  filtered.add(pts.last);

  List<Offset> current = filtered;
  for (int it = 0; it < iterations; it++) {
    if (current.length < 3) break;
    List<Offset> next = [current.first];
    for (int i = 0; i < current.length - 1; i++) {
      final p0 = current[i];
      final p1 = current[i + 1];

      final q = Offset(
        0.75 * p0.dx + 0.25 * p1.dx,
        0.75 * p0.dy + 0.25 * p1.dy,
      );
      final r = Offset(
        0.25 * p0.dx + 0.75 * p1.dx,
        0.25 * p0.dy + 0.75 * p1.dy,
      );

      next.add(q);
      next.add(r);
    }
    next.add(current.last);
    current = next;
  }
  return current;
}

void _buildAndCachePath(MathsPadLine line) {
  if (line.fillImage != null) {
    // Fill Tool result -- rendered as an image (see _drawStrokes), not a
    // stroked path, so there's nothing to build here.
    line.cachedBounds = line.fillWorldBounds;
    return;
  }
  if (line.points.isEmpty) return;

  if (line.points.length == 1) {
    final path = Path();
    path.addOval(
      Rect.fromCircle(
        center: line.points.first.offset,
        radius: line.strokeWidth / 2,
      ),
    );
    line.cachedPath = path;
    line.cachedBounds = Rect.fromCircle(
      center: line.points.first.offset,
      radius: line.strokeWidth / 2,
    );
    return;
  }

  if (line.isShape || line.points.length <= 2) {
    final path = Path();
    path.moveTo(line.points[0].offset.dx, line.points[0].offset.dy);
    for (int i = 1; i < line.points.length; i++) {
      path.lineTo(line.points[i].offset.dx, line.points[i].offset.dy);
    }
    line.cachedPath = path;
  } else {
    final List<Offset> rawOffsets = line.points.map((p) => p.offset).toList();
    final List<Offset> smoothPts = _chaikinSmooth(rawOffsets, iterations: 3);

    final path = Path();
    path.moveTo(smoothPts[0].dx, smoothPts[0].dy);

    for (int i = 1; i < smoothPts.length - 1; i++) {
      final pPrev = smoothPts[i];
      final pNext = smoothPts[i + 1];
      final midX = (pPrev.dx + pNext.dx) / 2;
      final midY = (pPrev.dy + pNext.dy) / 2;
      path.quadraticBezierTo(pPrev.dx, pPrev.dy, midX, midY);
    }

    final lastPrev = smoothPts[smoothPts.length - 2];
    final last = smoothPts.last;
    path.quadraticBezierTo(lastPrev.dx, lastPrev.dy, last.dx, last.dy);

    line.cachedPath = path;
  }

  double minX = line.points.first.offset.dx;
  double maxX = minX;
  double minY = line.points.first.offset.dy;
  double maxY = minY;
  for (int i = 1; i < line.points.length; i++) {
    final p = line.points[i].offset;
    if (p.dx < minX) minX = p.dx;
    if (p.dx > maxX) maxX = p.dx;
    if (p.dy < minY) minY = p.dy;
    if (p.dy > maxY) maxY = p.dy;
  }
  line.cachedBounds = Rect.fromLTRB(minX, minY, maxX, maxY);
}

// ── Layer 1: Finished Strokes & Background Painter ─────────────────────────────
class _MathsPadFinishedStrokesPainter extends CustomPainter {
  final List<MathsPadLine> lines;
  final CanvasBgMode bgMode;
  final bool isDark;
  final Color canvasBgColor;
  final Offset panOffset;
  final double scale;

  _MathsPadFinishedStrokesPainter({
    required this.lines,
    required this.bgMode,
    required this.isDark,
    required this.canvasBgColor,
    required this.panOffset,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    try {
      canvas.translate(panOffset.dx, panOffset.dy);
      canvas.scale(scale);

      final double startX = ((-panOffset.dx) / scale);
      final double endX = ((size.width - panOffset.dx) / scale);
      final double startY = ((-panOffset.dy) / scale);
      final double endY = ((size.height - panOffset.dy) / scale);

      // 1. Draw Paper Pattern
      final gridPaint = Paint()
        ..color = (isDark ? Colors.white : Colors.indigo).withOpacity(0.07)
        ..strokeWidth = 1.0 / scale;

      if (bgMode == CanvasBgMode.grid) {
        const double step = 28.0;
        final double gridStartX = (startX / step).floor() * step - step;
        final double gridEndX = (endX / step).ceil() * step + step;
        final double gridStartY = (startY / step).floor() * step - step;
        final double gridEndY = (endY / step).ceil() * step + step;

        for (double x = gridStartX; x <= gridEndX; x += step) {
          canvas.drawLine(
            Offset(x, gridStartY),
            Offset(x, gridEndY),
            gridPaint,
          );
        }
        for (double y = gridStartY; y <= gridEndY; y += step) {
          canvas.drawLine(
            Offset(gridStartX, y),
            Offset(gridEndX, y),
            gridPaint,
          );
        }
      } else if (bgMode == CanvasBgMode.ruled) {
        const double lineStep = 32.0;
        final double gridStartX =
            (startX / lineStep).floor() * lineStep - lineStep;
        final double gridEndX = (endX / lineStep).ceil() * lineStep + lineStep;
        final double lineStartY =
            (startY / lineStep).floor() * lineStep - lineStep;
        final double lineEndY = (endY / lineStep).ceil() * lineStep + lineStep;

        for (double y = lineStartY; y <= lineEndY; y += lineStep) {
          canvas.drawLine(
            Offset(gridStartX, y),
            Offset(gridEndX, y),
            gridPaint,
          );
        }
      }

      // 2. Viewport Spatial Culling Optimization
      final visibleLines = lines.where((line) {
        if (line.points.isEmpty) return false;
        if (line.cachedBounds == null) {
          double minX = line.points.first.offset.dx;
          double maxX = minX;
          double minY = line.points.first.offset.dy;
          double maxY = minY;
          for (int i = 1; i < line.points.length; i++) {
            final p = line.points[i].offset;
            if (p.dx < minX) minX = p.dx;
            if (p.dx > maxX) maxX = p.dx;
            if (p.dy < minY) minY = p.dy;
            if (p.dy > maxY) maxY = p.dy;
          }
          line.cachedBounds = Rect.fromLTRB(minX, minY, maxX, maxY);
        }
        final b = line.cachedBounds!;
        return b.right >= startX - 100 &&
            b.left <= endX + 100 &&
            b.bottom >= startY - 100 &&
            b.top <= endY + 100;
      }).toList();

      // 3. Render Strokes
      final bool hasPixelEraser = visibleLines.any((l) => l.isEraser);
      if (hasPixelEraser) {
        final Rect layerBounds = Rect.fromLTRB(
          startX - 100,
          startY - 100,
          endX + 100,
          endY + 100,
        );
        canvas.saveLayer(layerBounds, Paint());
        try {
          _drawStrokes(canvas, visibleLines);
        } finally {
          canvas.restore();
        }
      } else {
        _drawStrokes(canvas, visibleLines);
      }
    } finally {
      canvas.restore();
    }
  }

  void _drawStrokes(Canvas canvas, List<MathsPadLine> visibleLines) {
    for (final line in visibleLines) {
      if (line.fillImage != null && line.fillWorldBounds != null) {
        // Fill Tool result: draw the rasterized flood-fill image directly.
        // It only ever contains pixels for the region that was actually
        // filled (everything else in the cropped image is transparent), so
        // draw order relative to boundary strokes doesn't matter -- the
        // strokes that formed the boundary were never touched by the fill
        // and remain visible on top (or underneath) regardless.
        canvas.drawImageRect(
          line.fillImage!,
          Rect.fromLTWH(
            0,
            0,
            line.fillImage!.width.toDouble(),
            line.fillImage!.height.toDouble(),
          ),
          line.fillWorldBounds!,
          Paint(),
        );
        continue;
      }
      if (line.points.isEmpty) continue;

      final paint = Paint()
        ..isAntiAlias = true
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      if (line.isEraser) {
        paint.blendMode = BlendMode.clear;
        paint.strokeWidth = line.strokeWidth * 3.5;
      } else {
        paint.color = line.color;
        paint.strokeWidth = line.strokeWidth;
      }

      if (line.points.length == 1) {
        paint.style = PaintingStyle.fill;
        canvas.drawCircle(
          line.points.first.offset,
          paint.strokeWidth / 2,
          paint,
        );
      } else {
        if (line.cachedPath == null) {
          _buildAndCachePath(line);
        }

        if (!line.isEraser) {
          final softUnderPaint = Paint()
            ..isAntiAlias = true
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke
            ..color = line.color.withValues(alpha: 0.12)
            ..strokeWidth = line.strokeWidth * 1.35;
          canvas.drawPath(line.cachedPath!, softUnderPaint);
        }

        canvas.drawPath(line.cachedPath!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MathsPadFinishedStrokesPainter oldDelegate) {
    return true;
  }
}

// ── Layer 2: Active Live Drawing & Selection Overlay Painter ────────────────────
class _MathsPadActiveOverlayPainter extends CustomPainter {
  final MathsPadLine? currentLine;
  final Set<MathsPadLine> selectedLines;
  final List<Offset> lassoPoints;
  final Offset panOffset;
  final double scale;
  final BasicShapeType? activeShapeTool;
  final Offset? shapeDragStartPos;
  final Offset? shapeDragCurrentPos;
  final Color selectedColor;
  final double penWidth;
  final bool isDark;

  _MathsPadActiveOverlayPainter({
    required this.currentLine,
    required this.selectedLines,
    required this.lassoPoints,
    required this.panOffset,
    required this.scale,
    this.activeShapeTool,
    this.shapeDragStartPos,
    this.shapeDragCurrentPos,
    this.selectedColor = const Color(0xFF6366F1),
    this.penWidth = 3.0,
    required this.isDark,
  });

  Rect? _getGroupBounds(Set<MathsPadLine> selection) {
    if (selection.isEmpty) return null;
    double minX = double.infinity;
    double maxX = -double.infinity;
    double minY = double.infinity;
    double maxY = -double.infinity;

    for (final line in selection) {
      for (final p in line.points) {
        if (p.offset.dx < minX) minX = p.offset.dx;
        if (p.offset.dx > maxX) maxX = p.offset.dx;
        if (p.offset.dy < minY) minY = p.offset.dy;
        if (p.offset.dy > maxY) maxY = p.offset.dy;
      }
    }

    if (minX == double.infinity) return null;
    return Rect.fromLTRB(minX, minY, maxX, maxY).inflate(16.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    try {
      canvas.translate(panOffset.dx, panOffset.dy);
      canvas.scale(scale);

      // 1. Draw Active Stroke Live Path
      if (currentLine != null && currentLine!.points.isNotEmpty) {
        final line = currentLine!;
        final paint = Paint()
          ..isAntiAlias = true
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;

        if (line.isEraser) {
          paint.blendMode = BlendMode.clear;
          paint.strokeWidth = line.strokeWidth * 3.5;
        } else {
          paint.color = line.color;
          paint.strokeWidth = line.strokeWidth;
        }

        if (line.points.length == 1) {
          paint.style = PaintingStyle.fill;
          canvas.drawCircle(
            line.points.first.offset,
            paint.strokeWidth / 2,
            paint,
          );
        } else {
          final Path livePath = _buildLivePath(line);
          if (!line.isEraser) {
            final softUnderPaint = Paint()
              ..isAntiAlias = true
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..style = PaintingStyle.stroke
              ..color = line.color.withValues(alpha: 0.12)
              ..strokeWidth = line.strokeWidth * 1.35;
            canvas.drawPath(livePath, softUnderPaint);
          }
          canvas.drawPath(livePath, paint);
        }
      }

      // 2. Draw Selection Overlay Box & Handles
      _drawSelectionOverlay(canvas);

      // 3. Draw Lasso Loop
      if (lassoPoints.length > 1) {
        final lassoPath = Path();
        lassoPath.moveTo(lassoPoints.first.dx, lassoPoints.first.dy);
        for (int i = 1; i < lassoPoints.length; i++) {
          lassoPath.lineTo(lassoPoints[i].dx, lassoPoints[i].dy);
        }
        lassoPath.close();

        final fillPaint = Paint()
          ..color = const Color(0xFF6366F1).withOpacity(0.18)
          ..style = PaintingStyle.fill;

        final borderPaint = Paint()
          ..color = const Color(0xFF6366F1)
          ..strokeWidth = 2.0 / scale
          ..style = PaintingStyle.stroke;

        canvas.drawPath(lassoPath, fillPaint);
        canvas.drawPath(lassoPath, borderPaint);
      }

      // 4. Draw Active Shape Drag Preview
      if (activeShapeTool != null &&
          shapeDragStartPos != null &&
          shapeDragCurrentPos != null) {
        final Rect shapeRect = Rect.fromPoints(
          shapeDragStartPos!,
          shapeDragCurrentPos!,
        );
        final previewLines = _MathsPadWidgetState.generateShapeLinesInRect(
          activeShapeTool!,
          shapeRect,
          selectedColor,
          penWidth,
        );

        final previewPaint = Paint()
          ..color = selectedColor
          ..strokeWidth = penWidth
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

        final fillPreviewPaint = Paint()
          ..color = selectedColor.withOpacity(0.06)
          ..style = PaintingStyle.fill;

        canvas.drawRect(shapeRect, fillPreviewPaint);

        for (final line in previewLines) {
          if (line.points.length > 1) {
            final path = Path();
            path.moveTo(
              line.points.first.offset.dx,
              line.points.first.offset.dy,
            );
            for (int i = 1; i < line.points.length; i++) {
              path.lineTo(line.points[i].offset.dx, line.points[i].offset.dy);
            }
            canvas.drawPath(path, previewPaint);
          }
        }
      }
    } finally {
      canvas.restore();
    }
  }

  Path _buildLivePath(MathsPadLine line) {
    final path = Path();
    if (line.points.isEmpty) return path;

    path.moveTo(line.points[0].offset.dx, line.points[0].offset.dy);
    if (line.points.length == 2) {
      path.lineTo(line.points[1].offset.dx, line.points[1].offset.dy);
      return path;
    }

    for (int i = 1; i < line.points.length - 1; i++) {
      final pPrev = line.points[i].offset;
      final pNext = line.points[i + 1].offset;
      final midX = (pPrev.dx + pNext.dx) / 2;
      final midY = (pPrev.dy + pNext.dy) / 2;
      path.quadraticBezierTo(pPrev.dx, pPrev.dy, midX, midY);
    }
    path.lineTo(line.points.last.offset.dx, line.points.last.offset.dy);
    return path;
  }

  void _drawSelectionOverlay(Canvas canvas) {
    final selectionBounds = _getGroupBounds(selectedLines);
    if (selectionBounds != null) {
      final selectBoxPaint = Paint()
        ..color = const Color(0xFF6366F1)
        ..strokeWidth = 2.0 / scale
        ..style = PaintingStyle.stroke;
      final fillSelectPaint = Paint()
        ..color = const Color(0xFF6366F1).withOpacity(0.12)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(selectionBounds, const Radius.circular(10)),
        fillSelectPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(selectionBounds, const Radius.circular(10)),
        selectBoxPaint,
      );

      final Offset rotHandlePos = Offset(
        selectionBounds.center.dx,
        selectionBounds.top - 28.0 / scale,
      );

      final stemPaint = Paint()
        ..color = const Color(0xFF6366F1)
        ..strokeWidth = 1.8 / scale
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(selectionBounds.center.dx, selectionBounds.top),
        rotHandlePos,
        stemPaint,
      );

      final rotBgPaint = Paint()
        ..color = isDark ? const Color(0xFF1E293B) : Colors.white
        ..style = PaintingStyle.fill;
      final rotBorderPaint = Paint()
        ..color = const Color(0xFF6366F1)
        ..strokeWidth = 2.0 / scale
        ..style = PaintingStyle.stroke;
      final rotCenterDotPaint = Paint()
        ..color = const Color(0xFF6366F1)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(rotHandlePos, 8.0 / scale, rotBgPaint);
      canvas.drawCircle(rotHandlePos, 8.0 / scale, rotBorderPaint);
      canvas.drawCircle(rotHandlePos, 3.0 / scale, rotCenterDotPaint);

      final cornerBgPaint = Paint()
        ..color = isDark ? const Color(0xFF1E293B) : Colors.white
        ..style = PaintingStyle.fill;
      final cornerBorderPaint = Paint()
        ..color = const Color(0xFF6366F1)
        ..strokeWidth = 2.0 / scale
        ..style = PaintingStyle.stroke;

      final double cornerRadius = 6.0 / scale;
      final corners = [
        selectionBounds.topLeft,
        selectionBounds.topRight,
        selectionBounds.bottomLeft,
        selectionBounds.bottomRight,
      ];

      for (final corner in corners) {
        canvas.drawCircle(corner, cornerRadius, cornerBgPaint);
        canvas.drawCircle(corner, cornerRadius, cornerBorderPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MathsPadActiveOverlayPainter oldDelegate) {
    return true;
  }
}

class MathsPadFullScreenPage extends StatelessWidget {
  final String? questionText;
  final List<MathsPadLine>? initialLines;
  final bool enableSaveNotes;
  final String? noteId;
  final String? noteTitle;

  const MathsPadFullScreenPage({
    super.key,
    this.questionText,
    this.initialLines,
    this.enableSaveNotes = false,
    this.noteId,
    this.noteTitle,
  });

  static void open(
    BuildContext context, {
    String? questionText,
    List<MathsPadLine>? initialLines,
    bool enableSaveNotes = false,
    String? noteId,
    String? noteTitle,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MathsPadFullScreenPage(
          questionText: questionText,
          initialLines: initialLines,
          enableSaveNotes: enableSaveNotes,
          noteId: noteId,
          noteTitle: noteTitle,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.isDark
          ? const Color(0xFF0F172A)
          : const Color(0xFFFCFDFE),
      body: SafeArea(
        child: MathsPadWidget(
          questionText: questionText,
          isFullScreen: true,
          initialLines: initialLines,
          enableSaveNotes: enableSaveNotes,
          noteId: noteId,
          noteTitle: noteTitle,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}
