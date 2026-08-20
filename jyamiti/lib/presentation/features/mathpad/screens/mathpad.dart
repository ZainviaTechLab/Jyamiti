import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint, setEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:math_keyboard/math_keyboard.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import '../../../../services/stylus_prediction_service.dart';

import '../../../../providers/theme_provider.dart';
import '../instruments/instrument_models.dart';
import '../instruments/ruler_widget.dart';
import '../instruments/protractor_widget.dart';
import '../instruments/compass_widget.dart';
import '../instruments/set_square_widget.dart';
import '../instruments/graph_widget.dart';
import '../instruments/media_embed_models.dart';
import '../instruments/media_embed_widget.dart';
import '../recording/mathpad_recording_service.dart';
import '../asset_library/models/asset_library_models.dart';
import '../asset_library/models/mathpad_template_models.dart';
import '../asset_library/services/mathpad_asset_library_storage_service.dart';
import '../asset_library/screens/asset_library_picker_sheet.dart';
import '../widgets/student_spinner_dialog.dart';
import '../../../../providers/auth_provider.dart';

/// Hands the full current canvas content back to whoever opened
/// [MathsPadWidget] with a `onSaveRequested` callback (e.g. the Math Pad
/// Library's page editor) -- named params so call sites stay readable.
typedef MathsPadSaveCallback =
    Future<void> Function({
      required List<MathsPadLine> lines,
      required List<InstrumentState> instruments,
      required List<MathsPadTextLabel> textLabels,
      required List<MathsPadFixedAngleLabel> fixedAngleLabels,
      required CanvasBgMode bgMode,
      required MathPadTheme themeMode,
    });

/// A closure that reads the canvas's CURRENT (live, still-mutable) content
/// whenever it's called -- as opposed to [MathsPadSaveCallback], which is
/// only invoked once at an explicit save/close moment. Handed to
/// `onEditorReady` at [MathsPadWidget] init so an external page-switcher
/// (e.g. the Math Pad Library's multi-page editor) can silently snapshot
/// "whatever's on screen right now" before swapping in a different page,
/// without needing a save button press.
typedef MathsPadLiveStateReader =
    ({
      List<MathsPadLine> lines,
      List<InstrumentState> instruments,
      List<MathsPadTextLabel> textLabels,
      List<MathsPadFixedAngleLabel> fixedAngleLabels,
      CanvasBgMode bgMode,
      MathPadTheme themeMode,
    })
    Function();

class MathsPadStrokePoint {
  Offset offset;
  // Normalized (0..1) hardware stylus pressure at this point, or null when
  // the input device (mouse/touch/trackpad, or resampling like the Eraser's
  // stroke-cut) doesn't carry real pressure -- the Pencil tool then
  // simulates pressure from stroke velocity instead. Unrelated to
  // `_currentPointerPressure`'s pen-only fixed-width-multiplier use.
  final double? pressure;
  MathsPadStrokePoint(this.offset, [this.pressure]);
}

class MathsPadLine {
  final List<MathsPadStrokePoint> points;
  // Mutable so a selected stroke/shape can be recoloured in place from the
  // palette (see `_recolorSelectedLines`) without swapping in a new object
  // identity -- which would otherwise desync `_selectedLines` membership
  // and any `MathsPadFixedAngleLabel.sourceLines` reference to this line.
  Color color;
  final double strokeWidth;
  final bool isMagic;
  final bool isEraser;
  final bool isShape;
  // True for strokes drawn with the Pencil tool (perfect_freehand
  // pressure-sensitive filled outline) as opposed to the classic
  // constant-width Pen -- a completely separate rendering path, see
  // `_buildPencilOutlinePath`/`_paintInkLine`.
  final bool isPencil;

  // A Fill Tool result: a rasterized flood-fill of some enclosed region,
  // rendered as an image instead of a stroked path. When set, `points` holds
  // exactly 2 entries -- the world-space top-left and bottom-right corners of
  // `fillWorldBounds` -- purely so this line still participates in the
  // generic points-based bounds/culling/move/scale/copy machinery below
  // without any of it needing to know fills exist.
  ui.Image? fillImage;
  Rect? fillWorldBounds;
  // Radians, only meaningful when `fillImage != null` -- the image is
  // rendered rotated about its own `fillWorldBounds` center at paint time
  // (see `_MathsPadFinishedStrokesPainter.paint`); the bounds rect itself
  // stays axis-aligned and is
  double rotation;
  String? groupId;

  // True for a user-pasted image (`_insertPastedImageBytes`), false for a
  // Fill Tool flood-fill result -- both share the `fillImage` mechanism
  // above, but render with different z-order rules (see
  // `_MathsPadFinishedStrokesPainter.paint`'s Pass 1 vs Pass 2): a Fill
  // Tool patch always stays underneath every stroke (so ink's own
  // antialiased edge blends on top of it), while a pasted image renders
  // in true chronological order right alongside ink -- draw a stroke
  // after pasting an image and that stroke stays on top of it, same as
  // pasting a second image on top of an earlier one or earlier ink. The
  // Eraser tool can never affect either kind of image regardless of this
  // flag or draw order.
  bool isPastedImage;

  Path? cachedPath;
  Rect? cachedBounds;

  // Live-drawing-only scratch state (never serialized, never touched by
  // `invalidateCache`/`cachedPath` above -- those are for the FINAL
  // committed stroke's path) -- see `_buildLivePath`'s use of these to
  // avoid re-running full Chaikin smoothing over the entire stroke-so-far
  // on every single drawing frame.
  List<Offset>? liveCachedSmoothPts;
  int liveCachedRawPointCount = 0;

  // How many of this (still being drawn) line's leading raw points are
  // already rasterized into Layer 2a's cached "stroke-so-far" snapshot
  // (see `_kLiveBakeEvery`) -- 0 until the first bake. Meaningless once
  // the stroke is committed into `_lines`/a baked chunk, which render
  // from `cachedPath` above instead.
  int liveBakedPointCount = 0;

  MathsPadLine({
    required this.points,
    required this.color,
    required this.strokeWidth,
    this.isMagic = false,
    this.isEraser = false,
    this.isShape = false,
    this.isPencil = false,
    this.fillImage,
    this.fillWorldBounds,
    this.rotation = 0,
    this.groupId,
    this.cachedPath,
    this.cachedBounds,
    this.isPastedImage = false,
  });

  void invalidateCache() {
    cachedPath = null;
    cachedBounds = null;
    // Keep the rendered image's rect in sync after a move/resize drag (both
    // just translate/scale `points` in place).
    if (fillImage != null && points.length >= 2) {
      fillWorldBounds = Rect.fromPoints(points[0].offset, points[1].offset);
    }
    // `_buildLivePath`'s smoothing cache is staleness-checked purely by
    // RAW POINT COUNT (see its doc comment) -- correct for a live-growing
    // stroke, where the count only ever goes up, but WRONG for an
    // already-finished line being moved/rotated/resized: the count stays
    // fixed while every point's VALUE changes, so without clearing this
    // here too, `_buildLivePath` would keep reusing the smoothed shape
    // from whatever position the line was in the FIRST time it was
    // called after selection -- e.g. the selected-stroke neon outline
    // (which falls back to `_buildLivePath` once `cachedPath` is null)
    // would visibly freeze at the drag's starting position instead of
    // tracking the live move/rotate.
    liveCachedSmoothPts = null;
    liveCachedRawPointCount = 0;
  }
}

/// A typed text label placed on the canvas (e.g. "A", "5 cm", "∠ABC") --
/// draggable and re-editable, independent of the freehand stroke system.
class MathsPadTextLabel {
  Offset position; // world-space, top-left anchor
  String text;
  Color color;
  double fontSize;
  bool isEquation;
  final GlobalKey renderKey = GlobalKey();

  MathsPadTextLabel({
    required this.position,
    required this.text,
    required this.color,
    this.fontSize = 20,
    this.isEquation = false,
  });

  Size get measuredSize {
    if (renderKey.currentContext != null) {
      final box = renderKey.currentContext!.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        // The Stack's exact painted size
        return box.size;
      }
    }

    // Fallback if not rendered yet
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
  pencil,
  straightLine,
  angle,
  polygonAngle,
  circleArc,
  square,
  fill,
  text,
  equation,
  spacer,
  eraser,
  tapSelect,
  lasso,
  pan,
  laser,
}

// How long a single Laser Pointer trail point stays visible (fading out
// over this whole window) before being dropped -- shared by the state's
// prune timer and the painter's fade calculation so they never drift apart.
const int _kLaserTrailLifetimeMs = 550;

/// One point along a Laser Pointer trail -- purely a transient visual (never
/// added to `_lines`, never touches undo history, saves/exports, or
/// recordings' permanent content) that fades out on its own shortly after
/// being laid down, the same way a real presentation laser pointer's glow
/// doesn't leave a mark.
class _LaserTrailPoint {
  final Offset pos;
  final int bornAtMs;
  _LaserTrailPoint(this.pos, this.bornAtMs);
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

enum CanvasBgMode { grid, ruled, blank }

// "Aswad Lail" (أسود ليل, Arabic for "black night") -- a pure-black theme,
// #000000, distinct from the dark-navy `dark` theme.
enum MathPadTheme { light, dark, cosmos, aswadLail }

enum BasicShapeType {
  circle,
  square,
  rectangle,
  triangle,
  rightTriangle,
  pentagon,
  hexagon,
  diamond,
  coordinateAxes,
  arrowHorizontal,
  arrowVertical,
  cube3d,
  cone3d,
  sphere3d,
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
class MathsPadFixedAngleLabel {
  // Mutable so the Spacer Tool can shift it along with its source lines
  // when they move.
  Offset vertex;
  final double startAngle; // radians, direction of the first ray
  final double sweepAngle; // signed radians, shortest path to the second ray
  final String text;
  // The two stroke objects that form this angle's rays. If either gets
  // erased/undone/deleted, this label is orphaned and should disappear too.
  final List<MathsPadLine> sourceLines;

  MathsPadFixedAngleLabel({
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
  final List<MathsPadFixedAngleLabel> angleLabels;
  final Map<MathsPadFixedAngleLabel, Offset> originalAngleVertices;
  // The most negative shift allowed -- how far the moving group can be
  // pulled back (closing the gap) before its nearest stroke edge would
  // touch the nearest stationary stroke's edge. 0 if there's nothing
  // stationary to collide with, so pulling back still just closes the gap
  // to nothing (the old behaviour) rather than going unbounded.
  final double minAllowedShift;

  _SpacerDragState({
    required this.isVertical,
    required this.startWorld,
    required this.lines,
    required this.originalLinePoints,
    required this.labels,
    required this.originalLabelPositions,
    required this.angleLabels,
    required this.originalAngleVertices,
    required this.minAllowedShift,
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

/// Paints a small semicircle-with-ticks glyph -- the "Add Protractor"
/// toolbar button's icon, since no stock Material icon actually looks like
/// a protractor. Mirrors the real `ProtractorWidget`'s shape/orientation
/// (flat edge along the bottom, arc bulging upward) at icon scale.
class _ProtractorIconPainter extends CustomPainter {
  final Color color;

  _ProtractorIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final double r = size.width / 2 - 1.5;
    // The semicircle's own bounding box spans from the flat edge (at
    // `center.dy`) up to `r` above it, so its vertical midpoint sits at
    // `center.dy - r / 2` -- placing the flat edge at `size.height / 2 +
    // r / 2` puts that midpoint exactly on the icon box's own centre,
    // instead of visually sitting high with too much empty space below.
    final Offset center = Offset(size.width / 2, size.height / 2 + r / 2);

    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final Path body = Path()
      ..moveTo(center.dx - r, center.dy)
      ..arcTo(Rect.fromCircle(center: center, radius: r), pi, pi, false)
      ..lineTo(center.dx + r, center.dy)
      ..close();
    canvas.drawPath(body, stroke);

    // A few degree ticks around the arc, like the real instrument's --
    // simplified to every 45° at icon scale.
    for (int deg = 0; deg <= 180; deg += 45) {
      final double theta = pi - (deg * pi / 180);
      final Offset dir = Offset(cos(theta), -sin(theta));
      canvas.drawLine(center + dir * r, center + dir * (r - 3), stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _ProtractorIconPainter oldDelegate) =>
      oldDelegate.color != color;
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
  _ShapeToolItem(
    BasicShapeType.cone3d,
    Icons.filter_tilt_shift_rounded,
    '3D Cone',
  ),
  _ShapeToolItem(BasicShapeType.sphere3d, Icons.language_rounded, '3D Sphere'),
];

class _CanvasCluster {
  final List<MathsPadLine> lines = [];
  final List<MathsPadTextLabel> labels = [];
  Rect bounds;
  Offset totalShift = Offset.zero;

  _CanvasCluster(this.bounds);

  void merge(_CanvasCluster other) {
    lines.addAll(other.lines);
    labels.addAll(other.labels);
    bounds = bounds.expandToInclude(other.bounds);
  }

  void shift(Offset offset) {
    for (final line in lines) {
      if (line.fillImage != null && line.fillWorldBounds != null) {
        line.fillWorldBounds = line.fillWorldBounds!.shift(offset);
      }
      for (final p in line.points) {
        p.offset += offset;
      }
      line.cachedPath = null;
      line.cachedBounds = null;
      _buildAndCachePath(line);
    }
    for (final label in labels) {
      label.position += offset;
    }
    bounds = bounds.shift(offset);
    totalShift += offset;
  }
}

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

  // Math Pad Library hooks (see `mathpad/library/`): let a caller restore
  // the FULL canvas content of a saved page (not just strokes) and save it
  // back out. All optional -- omitting them leaves every existing caller's
  // behavior unchanged.
  final List<InstrumentState>? initialInstruments;
  final List<MathsPadTextLabel>? initialTextLabels;
  final List<MathsPadFixedAngleLabel>? initialFixedAngleLabels;
  final CanvasBgMode? initialBgMode;
  final MathPadTheme? initialThemeMode;
  final MathsPadSaveCallback? onSaveRequested;
  // Called once at init with a closure the caller can invoke at any later
  // moment to read this pad's CURRENT content -- used by the Math Pad
  // Library's page switcher to silently save "whatever's on screen" before
  // swapping in a different page, without a save-button press.
  final ValueChanged<MathsPadLiveStateReader>? onEditorReady;
  // Called once at init with a closure the caller can invoke at any later
  // moment (typically right after a save) to capture a small PNG
  // thumbnail of the canvas's CURRENT content -- same "hand out a
  // callable closure once" pattern as `onEditorReady`, just async, since
  // rasterizing a frame (`RenderRepaintBoundary.toImage`) can't be done
  // synchronously. Used by the Math Pad Library's page editor to keep
  // each page's cached preview image (see `MathPadLibraryStorageService.
  // saveThumbnail`) up to date without the pages sidebar ever needing to
  // decode/re-render a page's full stroke data just to show a thumbnail.
  final ValueChanged<Future<Uint8List?> Function()>? onThumbnailCaptureReady;
  // Fires whenever this pad's own "canvas only" mode (its internal
  // toolbar hidden down to a small pull-handle -- see `_isFullScreenMode`)
  // is toggled, so a caller with its OWN floating chrome around this
  // widget (e.g. the Math Pad Library page editor's book/page-preview
  // buttons and page-switcher bar) can hide that too while it's active.
  final ValueChanged<bool>? onCanvasOnlyModeChanged;
  final Widget? leadingToolbarAction;
  final Widget? trailingToolbarAction;

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
    this.initialInstruments,
    this.initialTextLabels,
    this.initialFixedAngleLabels,
    this.initialBgMode,
    this.initialThemeMode,
    this.onSaveRequested,
    this.onEditorReady,
    this.onThumbnailCaptureReady,
    this.onCanvasOnlyModeChanged,
    this.leadingToolbarAction,
    this.trailingToolbarAction,
  });

  @override
  State<MathsPadWidget> createState() => _MathsPadWidgetState();
}

class MathsPadAction {
  final List<MathsPadLine> addedLines;
  final List<MathsPadLine> removedLines;
  final List<MathsPadTextLabel> addedLabels;
  final List<MathsPadTextLabel> removedLabels;
  final List<InstrumentState> addedInstruments;
  final List<InstrumentState> removedInstruments;

  MathsPadAction({
    this.addedLines = const [],
    this.removedLines = const [],
    this.addedLabels = const [],
    this.removedLabels = const [],
    this.addedInstruments = const [],
    this.removedInstruments = const [],
  });

  void undo(_MathsPadWidgetState state) {
    if (addedLines.isNotEmpty)
      state._lines.removeWhere((l) => addedLines.contains(l));
    if (removedLines.isNotEmpty) {
      state._lines.addAll(removedLines);
      for (final l in removedLines) {
        _buildAndCachePath(l);
      }
    }

    if (addedLabels.isNotEmpty)
      state._textLabels.removeWhere((l) => addedLabels.contains(l));
    if (removedLabels.isNotEmpty) state._textLabels.addAll(removedLabels);

    if (addedInstruments.isNotEmpty)
      state._instruments.removeWhere((i) => addedInstruments.contains(i));
    if (removedInstruments.isNotEmpty)
      state._instruments.addAll(removedInstruments);

    state._selectedLines.removeWhere((l) => addedLines.contains(l));
    if (addedLines.isNotEmpty) {
      state._removeOrphanedAngleLabels(addedLines);
    }
    state._resetBaking();
    state._finishedStrokesNotifier.value++;
    state._activeDrawingNotifier.value++;
  }

  void redo(_MathsPadWidgetState state) {
    if (removedLines.isNotEmpty) {
      state._lines.removeWhere((l) => removedLines.contains(l));
      state._selectedLines.removeWhere((l) => removedLines.contains(l));
      state._removeOrphanedAngleLabels(removedLines);
    }
    if (addedLines.isNotEmpty) {
      state._lines.addAll(addedLines);
      for (final l in addedLines) {
        _buildAndCachePath(l);
      }
    }

    if (removedLabels.isNotEmpty)
      state._textLabels.removeWhere((l) => removedLabels.contains(l));
    if (addedLabels.isNotEmpty) state._textLabels.addAll(addedLabels);

    if (removedInstruments.isNotEmpty)
      state._instruments.removeWhere((i) => removedInstruments.contains(i));
    if (addedInstruments.isNotEmpty)
      state._instruments.addAll(addedInstruments);

    state._resetBaking();
    state._finishedStrokesNotifier.value++;
    state._activeDrawingNotifier.value++;
  }
}

class _MathsPadWidgetState extends State<MathsPadWidget>
    with SingleTickerProviderStateMixin {
  final List<MathsPadLine> _lines = [];
  final List<MathsPadAction> _undoHistory = [];
  final List<MathsPadAction> _redoHistory = [];

  bool get _isDarkTheme {
    return _themeMode == MathPadTheme.cosmos ||
        _themeMode == MathPadTheme.dark ||
        _themeMode == MathPadTheme.aswadLail;
  }

  Color get _textColor => _isDarkTheme ? Colors.white : _darkPanelColor;

  Color get _darkPanelColor => _themeMode == MathPadTheme.aswadLail
      ? const Color(0xFF222222)
      : const Color(0xFF1E293B);

  Color get _darkPillColor => _themeMode == MathPadTheme.aswadLail
      ? const Color(0xFF121212)
      : const Color(0xFF0F172A);
  Color get _textColor70 =>
      _isDarkTheme ? Colors.white70 : _darkPanelColor.withOpacity(0.7);
  Color get _textColor60 =>
      _isDarkTheme ? Colors.white60 : _darkPanelColor.withOpacity(0.6);
  MathsPadLine? _currentLine;

  MouseCursor get _canvasCursor {
    switch (_toolMode) {
      case CanvasToolMode.pan:
        return _activePointers.isNotEmpty
            ? SystemMouseCursors.grabbing
            : SystemMouseCursors.grab;
      case CanvasToolMode.pen:
        // Standard OS arrow instead of the crosshair -- same as the Pencil
        // tool (which already falls through to `SystemMouseCursors.basic`
        // via the `default` case below).
        return SystemMouseCursors.basic;
      case CanvasToolMode.straightLine:
      case CanvasToolMode.angle:
      case CanvasToolMode.polygonAngle:
      case CanvasToolMode.circleArc:
      case CanvasToolMode.square:
      case CanvasToolMode.fill:
      case CanvasToolMode.laser:
      case CanvasToolMode.spacer:
        return SystemMouseCursors.precise;
      case CanvasToolMode.eraser:
        return SystemMouseCursors.none;
      case CanvasToolMode.text:
      case CanvasToolMode.equation:
        return SystemMouseCursors.text;
      case CanvasToolMode.tapSelect:
        // Standard OS "clickable" pointing-hand cursor -- matches the
        // tap-to-select interaction better than the plain arrow.
        return SystemMouseCursors.click;
      case CanvasToolMode.lasso:
      default:
        return SystemMouseCursors.basic;
    }
  }

  // Live cursor ring drawn on the (cheap, per-frame) active overlay layer
  // while an area-eraser stroke is being dragged -- see the comment at its
  // one write site in `_onScaleUpdate` for why this replaced repainting
  // the entire finished-strokes layer on every move sample.
  Offset? _eraserCursorPos;

  // Geometry instruments (ruler, protractor, compass, set squares) overlaid
  // on the canvas. See presentation/features/mathpad/instruments/.
  final List<InstrumentState> _instruments = [];

  // Asset Library: which embedded video/GIF (if any) currently has its
  // close button showing -- mirrors `_selectedTextLabelIndex`'s "tap to
  // reveal controls" pattern. Set in `_tryStartInstrumentDrag` when a
  // MediaEmbedState's 'move' handle is hit, cleared when tapping anywhere
  // else (see the pointer-down handler, alongside the text label
  // deselection it's modeled on).
  MediaEmbedState? _selectedMediaEmbed;
  final _assetLibraryStorage = MathPadAssetLibraryStorageService();
  // Populated lazily (first Asset Library open, or whenever an embedded
  // asset needs resolving) and refreshed each time the picker sheet opens
  // -- avoids a disk hit on every MediaEmbedWidget rebuild. Keyed by
  // AssetLibraryEntry.id, covers both presets and user-imported entries.
  final Map<String, AssetLibraryEntry> _assetLookupCache = {};
  // The canvas's own visible size (excludes the toolbar above it), kept up
  // to date by the LayoutBuilder in build() -- used to center newly-added
  // instruments in the actually-visible area rather than the whole widget
  // (which would incorrectly include the toolbar's height).
  Size _canvasSize = const Size(800, 600);
  Offset? _snappedEdgeStart;

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
  final List<MathsPadFixedAngleLabel> _fixedAngleLabels = [];

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
  // Tracks the sweep as a continuously-unwrapped angle (not the wrapped
  // -pi..pi `Offset.direction` value) so points can be densely interpolated
  // between two consecutive pointer events regardless of how far apart they
  // land -- otherwise a platform/input device that delivers coarser pointer
  // events (e.g. a physical mouse vs. a trackpad) produces a visibly
  // faceted arc instead of a smooth circle.
  double? _circleLastRawAngle;
  double _circleSweptAngle = 0;
  // The circle only "arms" (locks its radius and becomes ready to sweep an
  // arc) once the pointer has held still at some length for a full second --
  // any drag that never pauses that long never starts a circle at all.
  Timer? _circleHoldTimer;
  Offset? _circleHoldAnchor;

  // ─── Square Tool ──────────────────────────────────────────────────────
  // Same two-phase gesture as the Circle/Arc Tool: drag out one side (any
  // angle -- horizontal and vertical are just the common cases), hold
  // still for a second to lock its length, then keep dragging to either
  // side of that segment to pick which way a square of that same side
  // length extends. On release, only the square remains -- same discard
  // rule as the circle if it's never actually armed.
  Offset? _squareBaseStart;
  Offset? _squareBaseEnd; // live end while still dragging the initial side
  double _squareSideLength = 0;
  bool _squareHasArmed = false;
  List<Offset> _squareLivePoints = []; // the 4 (5, closed) corners once armed
  Timer? _squareHoldTimer;
  Offset? _squareHoldAnchor;

  // ─── Straight Line Tool ───────────────────────────────────────────────
  // When true, the line snaps to whichever of horizontal/vertical is closer
  // to the actual drag angle instead of following it freely. Toggled by
  // tapping the tool's own toolbar button again while it's already active
  // (same convention as the Eraser's Stroke/Area toggle).
  bool _lineAxisLocked = false;
  Offset? _straightLineLiveEnd;

  // When true, the toolbar docks as a vertical bar along the left edge
  // (rotated 90°) instead of the default horizontal bar across the top.
  bool _toolbarOnLeft = false;

  // When true, the canvas fills the entire screen and the toolbar is
  // hidden -- only a small pull-handle strip remains at the top. Tapping
  // that handle slides the full toolbar down into view (see
  // `_toolbarRevealedInFullScreen`) so every control, including the way
  // back out of full screen, is still reachable without permanently taking
  // up canvas space.
  bool _isFullScreenMode = false;
  bool _toolbarRevealedInFullScreen = false;
  // Full-screen-only floating "glass waterdrop" quick-tools bubble -- a
  // faster way to switch pen/lasso/colour or undo without pulling the
  // whole toolbar into view.
  bool _quickToolsExpanded = false;

  // ─── Spacer Tool ──────────────────────────────────────────────────────
  // Drag through a gap to push everything past that point further away,
  // live, opening up blank space to work in -- like "Add Space" in note
  // apps. Axis (vertical vs horizontal) is decided from the first ~8px of
  // apps. Axis (vertical vs horizontal) is decided from the first ~8px of
  // actual movement. _spacerDrag stays null until the axis is decided.
  // Tapping the tool's own toolbar button again will compress the canvas.
  Offset? _spacerPointerStart;
  _SpacerDragState? _spacerDrag;
  double _spacerLiveShift = 0;

  // ─── Text Label Tool ──────────────────────────────────────────────────
  final List<MathsPadTextLabel> _textLabels = [];

  // Dragging an existing label (always available, independent of the active
  // tool, matching how geometry instruments can always be dragged).
  int? _draggedTextLabelIndex;
  Offset? _textDragPointerStart;
  Offset? _textDragLabelStart;
  bool _textDragMoved = false;
  bool _textLabelWasAlreadySelected = false;

  // The currently "active" text label (tapped once) -- its close button
  // and resize handle only render while it holds this, per the user's
  // request that those controls not clutter every label all the time.
  int? _selectedTextLabelIndex;
  int? _resizingTextLabelIndex;
  double? _resizeStartFontSize;
  double? _resizeStartCornerDist;

  // The inline text-entry editor -- used both for a brand-new label
  // (_textEditingIndex == null) and for re-editing an existing one.
  bool _textEditorOpen = false;
  int? _textEditingIndex;
  Offset? _textEditorWorldPos;
  TextEditingController? _textEditorController;
  MathFieldEditingController? _mathEditorController;
  String _currentLatexString = '';

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

  // Split of the finished-strokes layer into a rarely-repainting "baked"
  // sub-layer (`_lines[0.._bakedLineCount)`, redrawn only when
  // `_bakedStrokesNotifier` fires) and a small "recent" sub-layer
  // (`_lines[_bakedLineCount..]`, redrawn on every `_finishedStrokesNotifier`
  // tick same as before). Plain sequential drawing was forcing a full
  // from-scratch redraw of literally every stroke on the page on every
  // single commit (`_finishedStrokesNotifier` already fired once per
  // completed stroke, by design, for the correct reason of showing the new
  // ink) -- on a heavily-used page that's a real, ever-growing O(total
  // strokes) cost paid on every single new stroke, exactly matching "gets
  // laggier the more the page has been drawn on".
  //
  // The baked sub-layer is itself split into fixed CHUNKS (`_bakedChunks`,
  // one immutable `List<MathsPadLine>` per past bake event), each rendered
  // in its OWN keyed `RepaintBoundary`/`CustomPaint` in the widget tree
  // (see `build`'s Layer 1a). A single monolithic baked layer would still
  // have to fully re-rasterize its ENTIRE sublist every time a new chunk
  // folds in -- reintroducing the exact per-stroke-count-scaling hitch this
  // cache exists to eliminate, just at 1/`_kBakeThreshold` the frequency
  // instead of never (this was confirmed against real usage: "smooth, then
  // one laggy commit like before, then smooth again" -- a periodic hitch
  // whose cost grows with how much of the page is already baked). Chunking
  // keeps each individual bake event's cost bounded to `_kBakeThreshold`
  // lines regardless of total page history, because a sealed chunk's
  // `List<MathsPadLine>` instance is never replaced or re-sliced once
  // created -- `_MathsPadFinishedStrokesPainter.shouldRepaint` compares
  // `lines` by `identical()`, so Flutter's compositor reuses that chunk's
  // already-rasterized layer for free on every later rebuild instead of
  // re-executing its paint calls.
  //
  // Any operation that MUTATES or REMOVES an existing (possibly-already-
  // baked) line -- undo/redo/erase/selection-transform/clear -- calls
  // `_resetBaking()` instead, discarding all sealed chunks and falling back
  // to the previous (correct, if unoptimized) full-recent-layer behavior
  // for those lower-frequency interactions rather than risk a baked chunk
  // silently going stale.
  int _bakedLineCount = 0;
  final List<List<MathsPadLine>> _bakedChunks = [];
  // True from `initState` until a freshly-opened page's `widget.
  // initialLines` have all been frame-batched into `_bakedChunks` (see
  // `_hydrateNextInitialBatch`) -- guards against drawing/undo/paste/etc.
  // interleaving with the hydration batches, which would corrupt
  // `_bakedLineCount` bookkeeping (hydration assumes it owns the front of
  // `_lines` until done). False immediately for a blank/small page (no
  // `initialLines`), so this adds zero overhead for the common case.
  bool _isHydratingInitialContent = false;

  // World-space bounding box for each entry in `_bakedChunks` (same
  // index), computed once when a chunk seals -- lets `build` pass an
  // `isVisible` flag into each chunk's painter so it can skip its own
  // drawing work (real Skia tessellation cost) when nowhere near the
  // current viewport, WITHOUT ever unmounting the widget itself. An
  // earlier attempt achieved the same skip by excluding invisible chunks
  // from the `Stack`'s children entirely -- reverted, because destroying
  // and recreating a chunk's `RepaintBoundary`/GPU layer every time it
  // crossed the viewport edge caused a delayed "everything freezes for a
  // stretch a few seconds later" stall (GPU resource churn catching up),
  // confirmed by the user after that change. Keeping every chunk
  // permanently mounted and only toggling a paint-time boolean avoids that
  // churn entirely while still skipping the real cost.
  final List<Rect> _bakedChunkBounds = [];
  late final ValueNotifier<int> _bakedStrokesNotifier;
  static const int _kBakeThreshold = 25;
  // Caps how many separate `_bakedChunks` entries exist at once -- each is
  // its own composited GPU layer (`RepaintBoundary`), and confirmed via a
  // live diagnostic capture that COMPOSITING many of them together every
  // frame has a real, sustained cost that scales with zoom, independent of
  // whether any of them actually need to repaint: a 1670-line page (67
  // chunks at the old uncapped-count design) showed ~500ms of raster time
  // on nearly EVERY frame while zoomed in and drawing, even though the
  // live stroke painter itself measured under 1ms and no new chunk was
  // being created -- that sustained cost is what was actually behind
  // "after zooming, drawing/panning feels very very laggy," not repaint
  // work. `_kBakeThreshold` stays small (good per-stroke "recent" tier
  // redraw cost, unaffected by this), but once sealed, chunks periodically
  // get merged (see `_compactBakedChunksIfNeeded`) to keep the total
  // layer count bounded regardless of how large a page's history grows --
  // free to do since a baked chunk never needs to repaint on its own
  // (only on the rare frame it's first created/merged), so merging costs
  // nothing ongoing, only a one-time re-render of the merged result.
  static const int _kMaxBakedChunks = 24;

  /// Keeps `_bakedChunks.length` bounded to `_kMaxBakedChunks` by
  /// repeatedly merging the two OLDEST chunks into one -- cheap (just list
  /// concatenation + a bounds union, no painting happens here) since a
  /// chunk is only ever actually re-tessellated the next time it's
  /// rendered (via the normal `identical()`-based `shouldRepaint` check),
  /// not at merge time. Oldest-first means long-settled, effectively-
  /// static content naturally consolidates into fewer, larger layers over
  /// a page's lifetime, while freshly-baked chunks stay small until they
  /// too age into the merge -- content that's unlikely to ever need
  /// repainting again doesn't need to stay in its own separate layer.
  void _compactBakedChunksIfNeeded() {
    while (_bakedChunks.length > _kMaxBakedChunks) {
      final List<MathsPadLine> merged = [
        ..._bakedChunks[0],
        ..._bakedChunks[1],
      ];
      final Rect mergedBounds = _bakedChunkBounds[0].expandToInclude(
        _bakedChunkBounds[1],
      );
      _bakedChunks[0] = merged;
      _bakedChunkBounds[0] = mergedBounds;
      _bakedChunks.removeAt(1);
      _bakedChunkBounds.removeAt(1);
    }
  }

  Rect _computeLineBounds(MathsPadLine line) {
    if (line.points.isEmpty) return Rect.zero;
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
    return line.cachedBounds!;
  }

  /// Unions the world-space bounds of every line in [chunk] (computing and
  /// caching each line's own `cachedBounds` first if it isn't already, the
  /// same lazy bounds computation `_MathsPadFinishedStrokesPainter` does).
  Rect _computeChunkBounds(List<MathsPadLine> chunk) {
    Rect? bounds;
    for (final line in chunk) {
      if (line.points.isEmpty) continue;
      final lineBounds = line.cachedBounds ?? _computeLineBounds(line);
      bounds = bounds == null ? lineBounds : bounds.expandToInclude(lineBounds);
    }
    return bounds ?? Rect.zero;
  }

  void _maybeRebakeLines() {
    // MUST cap every sealed chunk at `_kBakeThreshold` -- this used to bake
    // the ENTIRE unbaked backlog (`_lines.sublist(_bakedLineCount,
    // _lines.length)`) in one shot, which is harmless when called after
    // every single stroke (the backlog is normally only ~25-26 lines when
    // the threshold trips) but a real, serious bug whenever a much larger
    // backlog piles up unbaked at once -- e.g. right after `_resetBaking()`
    // wipes everything on a heavy page, or after a bulk insert (paste/
    // duplicate/template). Confirmed via live diagnostic capture: a single
    // resulting "chunk" of 1604 lines took 873ms to paint, and kept getting
    // rebuilt from scratch on subsequent frames (its `lines` reference
    // changing each time defeats `shouldRepaint`'s `identical()` check) --
    // this is what was actually behind "after zooming/editing, everything
    // feels terrible," not zoom itself. Looping here bounds every chunk to
    // the same small, cheap-to-paint, stable size regardless of how large
    // the backlog is.
    bool sealedAny = false;
    while (_lines.length - _bakedLineCount >= _kBakeThreshold) {
      final int end = (_bakedLineCount + _kBakeThreshold).clamp(
        0,
        _lines.length,
      );
      final List<MathsPadLine> newChunk = _lines.sublist(_bakedLineCount, end);
      _bakedChunks.add(newChunk);
      _bakedChunkBounds.add(_computeChunkBounds(newChunk));
      _bakedLineCount = end;
      sealedAny = true;
    }
    if (sealedAny) {
      _compactBakedChunksIfNeeded();
      _bakedStrokesNotifier.value++;
    }
  }

  /// Processes one `_kBakeThreshold`-sized batch of `widget.initialLines`
  /// (building each line's smoothed `Path` via `_buildAndCachePath`,
  /// sealing the batch into a new baked chunk) and reschedules itself for
  /// the frame after next via `addPostFrameCallback`, until every loaded
  /// line has been hydrated -- see the doc comment at its call site in
  /// `initState` for why this replaced one flat synchronous loop over the
  /// whole page. `addPostFrameCallback` (rather than a microtask/`Future.
  /// delayed(Duration.zero)`) is deliberate: it deterministically waits
  /// for an actual rendered frame between batches, which is what lets a
  /// real loading indicator (and each newly-sealed chunk) actually be
  /// seen on screen between batches, not just theoretically yield.
  void _hydrateNextInitialBatch(Duration _) {
    if (!mounted) return;
    final int start = _bakedLineCount;
    final int end = (start + _kBakeThreshold).clamp(0, _lines.length);
    if (start >= end) {
      // Nothing left (or nothing to begin with) -- shouldn't normally be
      // reached given the `_lines.isNotEmpty` guard at the call site, but
      // safe to just stop hydrating rather than loop forever.
      if (_isHydratingInitialContent) {
        setState(() => _isHydratingInitialContent = false);
      }
      return;
    }
    final List<MathsPadLine> chunk = _lines.sublist(start, end);
    for (final line in chunk) {
      _buildAndCachePath(line);
    }
    _bakedChunks.add(chunk);
    _bakedChunkBounds.add(_computeChunkBounds(chunk));
    _bakedLineCount = end;
    // Keeps the total composited-layer count bounded even for a heavy
    // page's initial load, not just for later live drawing -- see
    // `_kMaxBakedChunks`'s doc comment.
    _compactBakedChunksIfNeeded();
    _bakedStrokesNotifier.value++;
    if (_bakedLineCount >= _lines.length) {
      setState(() => _isHydratingInitialContent = false);
    } else {
      SchedulerBinding.instance.addPostFrameCallback(_hydrateNextInitialBatch);
    }
  }

  void _resetBaking() {
    if (_bakedLineCount == 0 && _bakedChunks.isEmpty) return;
    _bakedLineCount = 0;
    _bakedChunks.clear();
    _bakedChunkBounds.clear();
    _bakedStrokesNotifier.value++;
  }

  // Active Pointers tracking for Chrome Web Multi-Touch Panning
  final Map<int, Offset> _activePointers = {};
  Offset? _lastCentroid;

  // Hardware Stylus Side Barrel Button & Eraser Tip Detection
  bool _isStylusBarrelPressed = false;
  bool _isPrimaryBarrelPressed = false;
  bool _isSecondaryBarrelPressed = false;
  DateTime? _lastPrimaryBarrelPressTime;
  DateTime? _lastSecondaryBarrelPressTime;

  // Most recent raw pointer pressure (updated from the `Listener`'s raw
  // PointerEvents, since `ScaleStartDetails`/`ScaleUpdateDetails` -- what
  // actually drives stroke drawing -- carry no pressure info at all).
  // Devices without pressure sensing (mouse, plain touch) always report
  // 1.0, so this only ever changes pen behaviour on an actual
  // pressure-sensitive stylus.
  double _currentPointerPressure = 1.0;

  // Dedicated to the Pencil tool -- deliberately separate from
  // `_currentPointerPressure` above (the Pen's own fixed-per-stroke-width
  // mechanism). Normalized (0..1) via pressureMin/pressureMax and only
  // trusted from an actual stylus/inverted-stylus; null for mouse/touch/
  // trackpad, so the Pencil tool falls back to perfect_freehand's
  // velocity-based simulated pressure instead.
  double? _lastPencilStylusPressure;

  // Android-only Pen tool latency reduction (see `StylusPredictionService`
  // and `MainActivity.kt`'s `dispatchTouchEvent`) -- true exactly when the
  // last point in `_currentLine.points` is a speculative predicted point
  // rather than a real touch sample. Always stripped before a real point,
  // a tool/stroke change, or a commit ever sees it -- it must never reach
  // `_lines`, undo history, baking, or a save. Deliberately scoped to the
  // classic Pen only; Pencil, Eraser, and every other tool are untouched.
  bool _predictedTailPresent = false;

  void _onStylusPredictedDelta() {
    final Offset? delta = StylusPredictionService.instance.predictedDelta.value;
    if (delta == null ||
        _currentLine == null ||
        _currentLine!.isEraser ||
        _currentLine!.isPencil ||
        _toolMode != CanvasToolMode.pen ||
        _lastPointerWorldPos == null) {
      return;
    }
    // Defensive sanity clamp -- discard an implausibly large jump rather
    // than let a stale prediction (e.g. right after a 2-finger pan
    // releases back to single-pointer drawing, the native predictor's
    // internal history is momentarily stale) fling the speculative tail
    // far from the real stroke.
    if (delta.distance > 40.0) return;

    final Offset predictedWorldPos =
        _lastPointerWorldPos! +
        (widget.isTransparentBg ? delta : delta / _scale);

    if (_predictedTailPresent && _currentLine!.points.isNotEmpty) {
      _currentLine!.points.removeLast();
    }
    _currentLine!.points.add(MathsPadStrokePoint(predictedWorldPos));
    _predictedTailPresent = true;
    _activeDrawingNotifier.value++;
  }

  void _capturePencilStylusPressure(PointerEvent event) {
    final bool isStylus =
        event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;
    if (isStylus && event.pressureMax > event.pressureMin) {
      _lastPencilStylusPressure =
          ((event.pressure - event.pressureMin) /
                  (event.pressureMax - event.pressureMin))
              .clamp(0.0, 1.0);
    } else {
      _lastPencilStylusPressure = null;
    }
  }

  // ─── Pen Tool: auto-shape on hold ───────────────────────────────────────
  // While freehand drawing (ink only, not the eraser), pausing mid-stroke
  // for a beat snaps the stroke-so-far to a clean shape IF it already
  // looks roughly like one -- a straight line (an intentionally-straight
  // but slightly wobbly hand-drawn line, not real handwriting -- see
  // `_tryAutoStraightenPenLine`'s straightness check) or a circle/oval
  // (see `_tryAutoCircleifyPenLine`'s roundness check), tried in that
  // order. Same "draw and hold to correct" idea as OneNote's ink shapes.
  // Continued dragging after that keeps adjusting the shape to follow the
  // pointer (the line's endpoint, or the circle's radius) instead of
  // resuming freehand sampling.
  Timer? _penHoldTimer;
  Offset? _penHoldAnchor;
  bool _penAutoStraightened = false;
  bool _penAutoCircled = false;
  Offset? _penAutoCircleCenter;

  void _resetPenAutoShape() {
    _penHoldTimer?.cancel();
    _penHoldTimer = null;
    _penHoldAnchor = null;
    _penAutoStraightened = false;
    _penAutoCircled = false;
    _penAutoCircleCenter = null;
  }

  /// Fires after holding still for a second mid-freehand-stroke -- tries
  /// snapping to a circle first (see `_tryAutoCircleifyPenLine`), then
  /// falls back to a straight line if that didn't match.
  void _tryAutoShapePenLine(Offset holdPos) {
    if (_tryAutoCircleifyPenLine(holdPos)) return;
    _tryAutoStraightenPenLine(holdPos);
  }

  /// Builds a closed circle outline of [segments] straight edges (65
  /// points, first == last to close the loop) -- a high enough segment
  /// count to look smooth at any reasonable on-canvas size, while still
  /// being cheap to build/redraw live every frame during a resize drag.
  /// Shared by the initial snap and by continued-drag resizing.
  List<MathsPadStrokePoint> _circleOutlinePoints(
    Offset center,
    double radius, {
    int segments = 64,
  }) {
    return List.generate(segments + 1, (i) {
      final double a = (i / segments) * 2 * pi;
      return MathsPadStrokePoint(center + Offset(cos(a), sin(a)) * radius);
    });
  }

  /// If the stroke-so-far already looks roughly like a hand-drawn
  /// circle/oval, replaces it with a perfect circle sized to match what
  /// was actually drawn (matching OneNote's ink-shape recognition, not
  /// snapped to some fixed/preset size). Detection fits an ELLIPSE from
  /// the points' bounding box rather than a single radius from the
  /// centroid -- live testing showed real hand/mouse-drawn "circles" are
  /// naturally somewhat oval (up to ~40-70% radius variance from a
  /// centroid-based single-radius model, which rejected every real
  /// attempt); the bounding box's center and half-extents are a far more
  /// forgiving, robust fit for a genuinely round-ish freehand shape while
  /// still rejecting real scribbles. Returns whether it actually
  /// snapped. `_currentLine` is replaced (not mutated) with a fresh
  /// `isShape: true` line so it renders with clean straight edges
  /// between the generated circle points instead of the freehand
  /// painter's Chaikin smoothing subtly rounding/shrinking it -- `isShape`
  /// is `final`, set once at construction.
  bool _tryAutoCircleifyPenLine(Offset holdPos) {
    final line = _currentLine;
    if (line == null || line.points.length < 10) return false;

    double minX = line.points.first.offset.dx;
    double maxX = minX;
    double minY = line.points.first.offset.dy;
    double maxY = minY;
    for (final p in line.points) {
      if (p.offset.dx < minX) minX = p.offset.dx;
      if (p.offset.dx > maxX) maxX = p.offset.dx;
      if (p.offset.dy < minY) minY = p.offset.dy;
      if (p.offset.dy > maxY) maxY = p.offset.dy;
    }
    final double rx = (maxX - minX) / 2;
    final double ry = (maxY - minY) / 2;
    if (rx < 8 || ry < 8) return false; // too small (or too flat) to judge

    // Not too elongated -- a genuinely round-ish shape, not a long thin
    // sliver (the straight-line check is the right fallback for that).
    final double aspect = rx > ry ? rx / ry : ry / rx;
    if (aspect > 2.2) return false;

    final Offset center = Offset((minX + maxX) / 2, (minY + maxY) / 2);

    // Roundness check against the fitted ELLIPSE: for a point exactly on
    // it, `((x-cx)/rx)^2 + ((y-cy)/ry)^2 == 1`. Real wobble in an
    // intentionally round-ish freehand shape stays reasonably close to
    // 1; a scribble, or a shape that's round in the middle but pokes out
    // somewhere, doesn't.
    const double allowedNormDeviation = 0.35;
    double worstNormDeviation = 0;
    for (final p in line.points) {
      final double dx = (p.offset.dx - center.dx) / rx;
      final double dy = (p.offset.dy - center.dy) / ry;
      final double normDist = sqrt(dx * dx + dy * dy);
      final double dev = (normDist - 1.0).abs();
      if (dev > worstNormDeviation) worstNormDeviation = dev;
    }
    if (worstNormDeviation > allowedNormDeviation) return false;

    // Coverage check: the stroke has to actually sweep most of the way
    // around the center -- however round, a short arc/curve isn't a
    // circle. Buckets each point's angle (in the ellipse's own
    // normalized frame, so wedges stay evenly spaced regardless of how
    // elongated it is) into 12 (30°) wedges and requires most to be hit.
    final List<bool> wedgesHit = List.filled(12, false);
    for (final p in line.points) {
      final double dx = (p.offset.dx - center.dx) / rx;
      final double dy = (p.offset.dy - center.dy) / ry;
      final double angle = atan2(dy, dx); // -pi..pi
      final int wedge = (((angle + pi) / (2 * pi)) * 12).floor().clamp(0, 11);
      wedgesHit[wedge] = true;
    }
    if (wedgesHit.where((hit) => hit).length < 9) return false;

    // The OUTPUT is still a perfect (not elliptical) circle -- sized to
    // the average of the fitted ellipse's two half-extents, which is
    // "accurate" to what was actually drawn without carrying the
    // detection step's extra tolerance for ovalness into the result
    // shape itself.
    final double outputRadius = (rx + ry) / 2;
    setState(() {
      _currentLine = MathsPadLine(
        points: _circleOutlinePoints(center, outputRadius),
        color: line.color,
        strokeWidth: line.strokeWidth,
        isMagic: line.isMagic,
        isShape: true,
      );
      _penAutoCircled = true;
      _penAutoCircleCenter = center;
    });
    _activeDrawingNotifier.value++;
    return true;
  }

  /// Fires after holding still for a second mid-freehand-stroke (and
  /// `_tryAutoCircleifyPenLine` didn't already match). If what's been
  /// drawn so far already looks roughly straight, snaps it to a perfect
  /// straight line from the stroke's start to the hold point, and flips
  /// on `_penAutoStraightened` so `_onScaleUpdate` keeps the line
  /// straight (following the pointer) for the rest of the drag instead of
  /// resuming freehand sampling.
  void _tryAutoStraightenPenLine(Offset holdPos) {
    final line = _currentLine;
    if (line == null || line.points.length < 3) return;

    final Offset start = line.points.first.offset;
    final double lineLen = (holdPos - start).distance;
    if (lineLen < 12) return; // too short to judge intent either way

    // Max perpendicular distance any drawn point strays from the straight
    // start->hold segment, as a fraction of that segment's length -- real
    // handwriting wanders far more than this; an intentionally-straight
    // but slightly wobbly hand-drawn line stays close to it.
    final Offset dir = (holdPos - start) / lineLen;
    final Offset perp = Offset(-dir.dy, dir.dx);
    double maxDeviation = 0;
    for (final p in line.points) {
      final Offset toPoint = p.offset - start;
      final double dist = (toPoint.dx * perp.dx + toPoint.dy * perp.dy).abs();
      if (dist > maxDeviation) maxDeviation = dist;
    }
    const double straightnessFraction = 0.12;
    final double allowedDeviation = (lineLen * straightnessFraction).clamp(
      4.0,
      40.0,
    );
    if (maxDeviation > allowedDeviation) return; // too curvy -- leave as-is

    setState(() {
      line.points
        ..clear()
        ..add(MathsPadStrokePoint(start))
        ..add(MathsPadStrokePoint(holdPos));
      _penAutoStraightened = true;
    });
    _activeDrawingNotifier.value++;
  }

  // Selected Lines & Move Drag State
  final Set<MathsPadLine> _selectedLines = {};
  bool _isDraggingSelection = false;
  Offset? _lastDragWorldPos;

  // Whatever tool was active right before double-tapping an image
  // auto-switched to the Select tool (see `_onScaleStart`'s double-tap
  // handling) -- null whenever that hasn't happened (or has already been
  // consumed/restored). Restored the next time an empty-canvas tap clears
  // the selection while still in the Select tool (see the `tapSelect`
  // branch just below), so double-tapping to peek at/adjust an image
  // doesn't strand the user in the Select tool afterward.
  CanvasToolMode? _toolModeBeforeDoubleTapImageSelect;

  // Stroke Clipboard for Copy (Ctrl+C) & Paste (Ctrl+V)
  List<MathsPadLine> _clipboard = [];
  Offset? _lastPointerWorldPos;
  int _consecutivePasteCount = 0;

  // Long-press -> "Paste" popup (touch equivalent of Ctrl+V). Detected
  // manually off the raw Listener pointer callbacks below rather than a
  // LongPressGestureRecognizer on the canvas's GestureDetector, since that
  // detector only wires Scale callbacks today -- adding a competing
  // long-press recognizer to the same arena would risk delaying every
  // quick tap across every tool (arena resolution isn't guaranteed to
  // settle before the long-press timeout). Raw pointer callbacks don't
  // participate in gesture-arena resolution, so this can't interfere with
  // any existing tool.
  Timer? _longPressPasteTimer;
  Timer? _rightToolbarHoverTimer;
  Timer? _rightToolbarHideTimer;
  bool _isRightToolbarVisible = false;
  Offset? _longPressPasteDownScreenPos;
  Offset? _pastePopupWorldPos;

  // Double-tap-to-select-image tracking -- deliberately timed off raw
  // `_onPointerDown` calls (same reasoning as the long-press-paste timer
  // above: no gesture-arena participation, so it can never delay/steal a
  // normal single tap from whatever tool is active) rather than
  // `GestureDetector.onDoubleTap`, which would introduce its own
  // resolution delay on EVERY single tap/stroke-start across the whole
  // canvas while it waits to see if a second tap follows. Consumed (and
  // reset to null) by `_onScaleStart`, which is where the actual
  // "select the image" action + skipping the normal draw-start happens.
  DateTime? _lastPointerDownTime;
  Offset? _lastPointerDownScreenPos;
  bool _isDoubleTapPointerDown = false;
  static const Duration _kDoubleTapMaxGap = Duration(milliseconds: 350);
  static const double _kDoubleTapMaxDistance = 25.0;

  // Keyboard FocusNode for Ctrl+C / Ctrl+V shortcuts
  final FocusNode _canvasFocusNode = FocusNode();

  // ─── Board + Voice Recording (Windows only) ────────────────────────────
  // See `MathPadRecordingService` -- the key is what lets it snapshot just
  // the canvas below, not the toolbar or anything outside this widget.
  final GlobalKey _canvasCaptureKey = GlobalKey();
  late MathPadRecordingService _recordingService;
  // Only tracks which of the handful of *structural* states recording is
  // in (idle/recording/waitingForEncodeChoice/encoding) -- used to gate
  // things elsewhere in the tree (button enabled state, `canPop`, whether
  // the badge/progress-bar widgets are even mounted). Kept in sync by
  // `_onRecordingServiceChanged`, which only `setState`s when this actual
  // value changes. Frequently-changing display values (elapsed time,
  // encoding progress/phase) deliberately do NOT live here any more --
  // `_buildRecordingBadge`/`_buildEncodingProgressBar` read those straight
  // off `_recordingService` themselves via `ListenableBuilder`, so a
  // once-a-second elapsed tick only rebuilds that small badge, not this
  // whole page. See `MathPadRecordingService._emitElapsedTick`'s doc
  // comment for why that distinction is what actually fixed recording-time
  // drawing stutter.
  MathPadRecordingState _recordingState = MathPadRecordingState.idle;
  // Opt-in toggle next to the record button -- OFF by default, so a
  // recording behaves exactly as it always has unless the tutor
  // explicitly turns this on before hitting Record. See
  // `MathPadRecordingService.start`'s `includeCamera`.
  bool _recordWithCamera = false;

  // A small pixel ratio, not the device's real one -- this is only ever
  // displayed at ~120px tall in the Math Pad Library's pages sidebar, so a
  // full-resolution capture would just be wasted disk space and encode
  // time for detail nobody can see at that size.
  static const double _kThumbnailPixelRatio = 0.25;

  /// One-off capture of the canvas's CURRENT content as a small PNG --
  /// handed out via `widget.onThumbnailCaptureReady` at init so the Math
  /// Pad Library's page editor can call it right after every save,
  /// persisting the result as that page's cached preview image (see
  /// `MathPadLibraryStorageService.saveThumbnail`). Same `RenderRepaintBoundary
  /// .toImage()`/`toByteData(png)` pattern `MathPadRecordingService.
  /// _captureFrame` already uses on this exact `_canvasCaptureKey` for video
  /// frames, just a single low-res call instead of a 60fps loop.
  Future<Uint8List?> _captureThumbnail() async {
    final RenderObject? renderObject = _canvasCaptureKey.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return null;
    final ui.Image image = await renderObject.toImage(
      pixelRatio: _kThumbnailPixelRatio,
    );
    try {
      final ByteData? bytes = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      return bytes?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  // Lasso Selection Points for Free-Select Area Erase & Move
  List<Offset> _lassoPoints = [];

  // Laser Pointer Tool: a fading trail, never a permanent stroke. Repainted
  // by a lightweight `Timer.periodic` (not tied to the drawing gesture)
  // since points must keep fading out even after the pointer stops moving;
  // the timer self-cancels once the trail is fully empty so it costs
  // nothing while the tool isn't in use.
  final List<_LaserTrailPoint> _laserTrail = [];
  Timer? _laserFadeTimer;

  // Neon selection outline: advanced by `_selectionGlowTimer` (set up in
  // initState) to animate the marching-dash motion traced around every
  // selected stroke.
  double _selectionGlowPhase = 0.0;
  Timer? _selectionGlowTimer;

  void _addLaserPoint(Offset worldPos) {
    _laserTrail.add(
      _LaserTrailPoint(worldPos, DateTime.now().millisecondsSinceEpoch),
    );
    _activeDrawingNotifier.value++;
    _laserFadeTimer ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      final int nowMs = DateTime.now().millisecondsSinceEpoch;
      final int before = _laserTrail.length;
      _laserTrail.removeWhere(
        (p) => nowMs - p.bornAtMs > _kLaserTrailLifetimeMs,
      );
      if (_laserTrail.length != before) {
        _activeDrawingNotifier.value++;
      }
      if (_laserTrail.isEmpty) {
        _laserFadeTimer?.cancel();
        _laserFadeTimer = null;
      }
    });
  }

  // Infinite Canvas Pan & Zoom Transformation State
  Offset _panOffset = Offset.zero;
  double _scale = 1.0;
  bool _zoomLocked = true;

  // Pan-direction lock (the "Floating Tool Hint Pill" lock icon, bottom
  // center of screen). When on, panning/scrolling can only reveal more
  // canvas below and to the right of wherever it was engaged, never back up/left past that point.
  // `_panLockWorldTopLeft` is the WORLD-space coordinate of the viewport's top-left corner at the
  // moment the lock was turned on -- pinning the boundary in world space
  // (not a raw screen-pixel pan offset) means it holds steady even if the
  // user zooms in/out while locked. See `_clampPanIfLocked`, which every
  // `_panOffset` assignment site routes through.
  bool _panLocked = true;
  Offset? _panLockWorldTopLeft = const Offset(0, 0);

  /// When `_panLocked` is on, clamps a proposed new `_panOffset` so it
  /// can't move the viewport's world-space top-left corner above/left of
  /// `_panLockWorldTopLeft` -- panning further right/down (which only
  /// DECREASES `_panOffset`) stays completely free.
  Offset _clampPanIfLocked(Offset proposed) {
    final Offset? lockTopLeft = _panLockWorldTopLeft;
    if (!_panLocked || lockTopLeft == null) return proposed;
    final double maxDx = -lockTopLeft.dx * _scale;
    final double maxDy = -lockTopLeft.dy * _scale;
    return Offset(
      proposed.dx > maxDx ? maxDx : proposed.dx,
      proposed.dy > maxDy ? maxDy : proposed.dy,
    );
  }

  // Gesture Tracking State
  Offset _initialFocalPoint = Offset.zero;
  Offset _initialPanOffset = Offset.zero;
  double _initialScale = 1.0;
  // True for the duration of a trackpad-driven pan/zoom gesture (see
  // `onPointerPanZoomStart/Update/End`) -- lets `_onScaleUpdate` skip its
  // own pan/zoom handling for the auto-synthesized calls
  // `ScaleGestureRecognizer` generates from the same underlying event
  // stream, since that synthesized data drifts for trackpad input (see
  // `_onScaleUpdate`'s doc comment).
  bool _isPanZoomGestureActive = false;
  // `event.scale`/`event.pan` value (both cumulative since gesture start)
  // as of the previous `onPointerPanZoomUpdate` call -- lets that handler
  // work with the INCREMENTAL, frame-to-frame change in each instead of
  // the accumulated-since-start value (see its doc comment for why that
  // matters for `pan` specifically).
  double _lastPanZoomScale = 1.0;
  Offset _lastPanZoomPan = Offset.zero;
  // Throttles how often a trackpad pan/zoom gesture actually pushes a new
  // value to `_scaleNotifier`/`_panNotifier` (see `_onTrackpadPanZoomUpdate`)
  // -- caps re-render frequency during a fast pinch to whatever the GPU can
  // realistically keep up with, instead of one render pass per raw
  // hardware sample. Set conservatively (~30fps) back when EVERY baked
  // chunk fully re-rendered on every zoom frame; now that Layer 1a
  // viewport-culls invisible chunks (see `_bakedChunkBounds`), the real
  // per-frame cost is bounded to just what's on screen, so this can afford
  // to run closer to a normal display's frame rate for smoother visual
  // feedback without reintroducing the backlog this throttle exists to
  // prevent.
  DateTime? _lastPanZoomNotifyTime;
  static const Duration _kPanZoomNotifyInterval = Duration(milliseconds: 16);

  CanvasToolMode _toolMode = CanvasToolMode.pen;
  bool _isMagicPenMode = false;
  Color _selectedColor = const Color(0xFF6366F1);
  double _penWidth = 3.0;
  double _pencilWidth = 6.0;
  double _eraserWidth = 14.0;
  double _selectedWidth = 3.0;
  CanvasBgMode _bgMode = CanvasBgMode.grid;
  MathPadTheme?
  _themeMode; // Null means follow System/App theme unless overridden by the user/saved state

  final List<Color> _palette = const [
    Color(0xFF6366F1), // Indigo
    Color(0xFFEC4899), // Pink
    Color(0xFF10B981), // Green
    Color(0xFFF59E0B), // Amber
    Color(0xFF3B82F6), // Blue
    Color(0xFFE71225), // Red
    Colors.white,
    Colors.black,
  ];

  // Small branding watermark drawn on the Ruler/Protractor/Set Squares.
  // Loaded once as a raw ui.Image (not an Image widget) so it can be drawn
  // straight into each instrument's own CustomPainter, inside the same
  // rotated canvas space as the rest of that instrument's body -- a plain
  // overlay widget wouldn't rotate along with the instrument.
  ui.Image? _logoImage;

  Future<void> _loadLogoImage() async {
    try {
      final ByteData data = await rootBundle.load('assets/image/logo.png');
      final ui.Codec codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
      );
      final ui.FrameInfo frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() => _logoImage = frame.image);
    } catch (_) {
      // Missing/unreadable asset -- instruments just render without the
      // watermark, nothing else depends on it.
    }
  }

  @override
  void initState() {
    super.initState();

    _loadLogoImage();
    if (widget.initialLines != null) {
      _lines.addAll(widget.initialLines!);
      // Immediately treat all pre-existing (loaded) content as "baked" --
      // otherwise a freshly-opened page with lots of prior strokes starts
      // with its ENTIRE history sitting in the small "recent" tier (see
      // `_bakedLineCount`/`_bakedChunks`), so every new stroke would
      // redraw the whole thing until enough new strokes accumulate to
      // trigger the first rebake -- exactly matching "laggy right after
      // opening, smooths out after drawing a bit". Chunking it up-front
      // the same way `_maybeRebakeLines` would (fixed `_kBakeThreshold`-
      // sized pieces, each its own permanently-sealed layer) means
      // drawing feels fast from the very first stroke instead of only
      // after the page's pre-existing content happens to get folded in.
      //
      // This USED to run as one flat synchronous loop over every line
      // right here -- for a heavy page (hundreds of lines), building each
      // one's smoothed `Path` (Chaikin smoothing + `quadraticBezierTo`
      // construction) back-to-back with zero yielding blocked the UI
      // thread for a real, user-visible stretch: the exact "page is stuck
      // for a while after opening, then it's fine" freeze. A loading
      // spinner alone couldn't fix that -- the same thread that would need
      // to be free to animate the spinner is the one being blocked.
      // Instead, hydrate in `_kBakeThreshold`-sized batches, one per
      // rendered frame (`_hydrateNextInitialBatch`), so the UI thread gets
      // to produce a frame (and animate a real loading indicator, see
      // `_isHydratingInitialContent`) between every ~25 lines' worth of
      // work instead of doing the whole page in one uninterrupted burst.
      // Each batch also seals one new chunk into `_bakedChunks` and bumps
      // `_bakedStrokesNotifier`, which -- for free, via the exact same
      // mechanism `_maybeRebakeLines` already uses -- spreads the
      // page's first-ever Skia rasterization across those same frames
      // too, instead of it all landing on a single frame once hydration
      // "finishes".
      if (_lines.isNotEmpty) {
        _isHydratingInitialContent = true;
        SchedulerBinding.instance.addPostFrameCallback(
          _hydrateNextInitialBatch,
        );
      }
    }
    if (widget.initialBgMode != null) {
      _bgMode = widget.initialBgMode!;
    } else if (widget.isInline) {
      _bgMode = CanvasBgMode.blank;
    }
    if (widget.initialThemeMode != null) {
      _themeMode = widget.initialThemeMode!;
    } else {
      _themeMode =
          MathPadTheme.light; // The user requested light theme as default
    }

    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      if (widget.initialThemeMode == null) {
        final savedTheme = prefs.getString('mathpad_default_theme');
        if (savedTheme != null) {
          setState(() {
            _themeMode = MathPadTheme.values.firstWhere(
              (e) => e.name == savedTheme,
              orElse: () => MathPadTheme.light,
            );
          });
        }
      }
      final savedPanLocked = prefs.getBool('mathpad_pan_locked');
      setState(() {
        _panLocked = savedPanLocked ?? true;
        _panLockWorldTopLeft = _panLocked
            ? Offset(-_panOffset.dx / _scale, -_panOffset.dy / _scale)
            : null;
      });
    });
    if (widget.initialInstruments != null) {
      _instruments.addAll(widget.initialInstruments!);
      // Any restored `MediaEmbedState`s need their `assetId` resolved
      // against the global Asset Library before `MediaEmbedWidget` can
      // render real content instead of a "missing asset" placeholder.
      if (_instruments.any((i) => i is MediaEmbedState)) {
        _ensureAssetLookupCacheLoaded().then((_) {
          if (mounted) setState(() {});
        });
      }
    }
    if (widget.initialTextLabels != null) {
      _textLabels.addAll(widget.initialTextLabels!);
    }
    if (widget.initialFixedAngleLabels != null) {
      _fixedAngleLabels.addAll(widget.initialFixedAngleLabels!);
    }
    if (widget.initialBgMode != null) {
      _bgMode = widget.initialBgMode!;
    } else if (widget.isTransparentBg) {
      _bgMode = CanvasBgMode.blank;
    }
    _panNotifier = ValueNotifier<Offset>(_panOffset);
    _scaleNotifier = ValueNotifier<double>(_scale);
    _finishedStrokesNotifier = ValueNotifier<int>(0);
    _bakedStrokesNotifier = ValueNotifier<int>(0);
    _activeDrawingNotifier = ValueNotifier<int>(0);
    _frictionController = AnimationController(vsync: this);
    // Drives the selected-stroke neon outline's marching-dash motion.
    // Runs for the widget's whole lifetime but only does any real work
    // (advancing the phase, triggering a repaint) while something is
    // actually selected -- otherwise this tick is just a cheap boolean
    // check, so there's no cost to leaving it running idle. Frozen (phase
    // simply stops advancing, outline stays put at whatever colour it was
    // already showing) for as long as a move/rotate/resize drag is
    // actively in progress -- the gradient's own continuous motion on top
    // of the outline ALSO continuously repositioning every frame reads as
    // messy/janky together, and makes it harder to tell the outline is
    // actually tracking the drag correctly. It resumes the instant the
    // drag ends.
    _selectionGlowTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (_selectedLines.isEmpty) return;
      final bool isTransforming =
          _isDraggingSelection || _activeHandle != SelectionHandleType.none;
      if (isTransforming) return;
      _selectionGlowPhase += 0.9;
      _activeDrawingNotifier.value++;
    });

    _recordingService = Provider.of<MathPadRecordingService>(
      context,
      listen: false,
    );

    _recordingState = _recordingService.state;
    if (_recordingState == MathPadRecordingState.recording) {
      _recordingService.updateCanvasKey(_canvasCaptureKey);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _recordingService.state == MathPadRecordingState.recording) {
          _recordingService.updateCanvasKey(_canvasCaptureKey);
        }
      });
    }

    _recordingService.addListener(_onRecordingServiceChanged);
    _recordingService.onCameraWarning = (message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.orange.shade800,
          duration: const Duration(seconds: 5),
        ),
      );
    };
    widget.onEditorReady?.call(
      () => (
        lines: _lines,
        instruments: _instruments,
        textLabels: _textLabels,
        fixedAngleLabels: _fixedAngleLabels,
        bgMode: _bgMode,
        themeMode:
            _themeMode ??
            (context.isDark ? MathPadTheme.dark : MathPadTheme.light),
      ),
    );
    widget.onThumbnailCaptureReady?.call(_captureThumbnail);

    StylusPredictionService.instance.ensureInitialized();
    StylusPredictionService.instance.predictedDelta.addListener(
      _onStylusPredictedDelta,
    );
  }

  void _onRecordingServiceChanged() {
    if (!mounted) return;
    // `MathPadRecordingService` now also notifies on a throttled once/sec
    // elapsed-time tick while recording (see `_emitElapsedTick`), which
    // this page has nothing to do with -- only an actual state transition
    // (idle -> recording -> ... ) needs the rest of the page (toolbar
    // enabled states, `canPop`, etc.) to rebuild. Skipping the no-op
    // `setState` on every other notification is what keeps a live
    // recording's timer ticks from touching the canvas/toolbar tree at
    // all.
    if (_recordingService.state == _recordingState) return;
    setState(() {
      _recordingState = _recordingService.state;
    });
  }

  @override
  void dispose() {
    StylusPredictionService.instance.predictedDelta.removeListener(
      _onStylusPredictedDelta,
    );
    _circleHoldTimer?.cancel();
    _longPressPasteTimer?.cancel();
    _rightToolbarHoverTimer?.cancel();
    _rightToolbarHideTimer?.cancel();
    _textEditorController?.dispose();
    _canvasFocusNode.dispose();
    _panNotifier.dispose();
    _scaleNotifier.dispose();
    _finishedStrokesNotifier.dispose();
    _bakedStrokesNotifier.dispose();
    _activeDrawingNotifier.dispose();
    _frictionController?.dispose();

    _recordingService.removeListener(_onRecordingServiceChanged);
    _laserFadeTimer?.cancel();
    _selectionGlowTimer?.cancel();
    super.dispose();
  }

  Future<void> _startRecording({required bool includeCamera}) async {
    if (_recordingState != MathPadRecordingState.idle) return;
    if (includeCamera) {
      final hasCam = await _recordingService.hasCamera();
      if (!hasCam) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No camera found -- check your webcam connection.'),
            backgroundColor: Colors.redAccent,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
    }
    setState(() => _recordWithCamera = includeCamera);
    try {
      await _recordingService.start(
        _canvasCaptureKey,
        includeCamera: includeCamera,
      );
    } on MathPadRecordingException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _stopRecording() async {
    if (_recordingState != MathPadRecordingState.recording) return;
    try {
      await _recordingService.stopCapture();
      final String path = await _recordingService.encode();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Recording saved to $path'),
          backgroundColor: const Color(0xFF10B981),
          duration: const Duration(seconds: 5),
        ),
      );
    } on MathPadRecordingException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 10),
        ),
      );
    }
  }

  String _formatRecordingElapsed(Duration d) {
    final int minutes = d.inMinutes;
    final int seconds = d.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
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
      _panOffset = _clampPanIfLocked(_frictionAnimation!.value);
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
      _recordAction(MathsPadAction(addedLines: [_currentLine!]));
      _finishedStrokesNotifier.value++;
      _maybeRebakeLines();
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

      final bool isVertical = delta.dy.abs() >= delta.dx.abs();
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
      final List<MathsPadFixedAngleLabel> affectedAngleLabels =
          _fixedAngleLabels
              .where((l) => l.sourceLines.any(affectedLineSet.contains))
              .toList();
      final Map<MathsPadFixedAngleLabel, Offset> originalAngleVertices = {
        for (final l in affectedAngleLabels) l: l.vertex,
      };

      // How far this drag can pull the moving group BACK (negative shift,
      // closing the gap) before its nearest stroke edge would touch the
      // nearest stationary stroke's edge -- using each stroke's actual ink
      // edge (centreline +/- half its width), not just centre points, so
      // "touch" means the ink visually meets rather than centrelines
      // crossing through each other.
      double stationaryMaxEdge = double.negativeInfinity;
      for (final line in _lines) {
        if (affectedLineSet.contains(line) || line.points.isEmpty) continue;
        final double halfWidth = line.strokeWidth / 2;
        final double lineMax = isVertical
            ? line.points.map((p) => p.offset.dy).reduce(max)
            : line.points.map((p) => p.offset.dx).reduce(max);
        final double edge = lineMax + halfWidth;
        if (edge > stationaryMaxEdge) stationaryMaxEdge = edge;
      }
      double movingMinEdge = double.infinity;
      for (final line in affectedLines) {
        final double halfWidth = line.strokeWidth / 2;
        final double lineMin = isVertical
            ? line.points.map((p) => p.offset.dy).reduce(min)
            : line.points.map((p) => p.offset.dx).reduce(min);
        final double edge = lineMin - halfWidth;
        if (edge < movingMinEdge) movingMinEdge = edge;
      }
      final double minAllowedShift =
          (stationaryMaxEdge.isFinite && movingMinEdge.isFinite)
          ? min(0.0, stationaryMaxEdge - movingMinEdge)
          : 0.0;

      _spacerDrag = _SpacerDragState(
        isVertical: isVertical,
        startWorld: start,
        lines: affectedLines,
        originalLinePoints: originalLinePoints,
        labels: affectedLabels,
        originalLabelPositions: originalLabelPositions,
        angleLabels: affectedAngleLabels,
        originalAngleVertices: originalAngleVertices,
        minAllowedShift: minAllowedShift,
      );
    }

    final _SpacerDragState drag = _spacerDrag!;
    final double rawShift = drag.isVertical
        ? worldPos.dy - drag.startWorld.dy
        : worldPos.dx - drag.startWorld.dx;
    // Dragging forward pushes content further away; dragging back past the
    // start now keeps closing the gap (going negative) until the moving
    // group's nearest stroke edge would touch the nearest stationary
    // stroke's edge, then stops there.
    final double shift = rawShift.clamp(drag.minAllowedShift, double.infinity);
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
      angleLabel.vertex = drag.originalAngleVertices[angleLabel]! + shiftOffset;
    }
    _finishedStrokesNotifier.value++;
    _resetBaking();
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

  /// Snaps [worldPos] (relative to [vertex]) so the angle it forms with
  /// [referenceDirection] (radians) lands on the nearest 0.5-degree
  /// increment -- keeps the raw drag distance untouched, only discretizes
  /// the angle, so the ray steps cleanly through 10.5°, 11.0°, 11.5°, ...
  /// instead of tracking every fractional degree the pointer happens to
  /// pass over. Used by both the Angle Tool's second line and the Polygon
  /// Angle Tool's joints.
  Offset _snapAngleToHalfDegree(
    Offset vertex,
    double referenceDirection,
    Offset worldPos,
  ) {
    final double distance = (worldPos - vertex).distance;
    if (distance < 1) return worldPos;
    final double rawOffset = _signedAngleDiff(
      referenceDirection,
      (worldPos - vertex).direction,
    );
    const double stepRad = 0.5 * pi / 180;
    final double snappedOffset = (rawOffset / stepRad).round() * stepRad;
    final double newDirection = referenceDirection + snappedOffset;
    return vertex + Offset(cos(newDirection), sin(newDirection)) * distance;
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
      final nearStart =
          _angleLineAStart != null &&
          (worldPos - _angleLineAStart!).distance <= vertexTolerance;
      final nearEnd =
          _angleLineAEnd != null &&
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

    Offset endPoint = worldPos;
    final bool isSecondLine =
        _angleWaitingForSecondLine &&
        _angleVertex != null &&
        _angleOtherEndOfA != null;
    if (isSecondLine) {
      endPoint = _snapAngleToHalfDegree(
        _angleVertex!,
        (_angleOtherEndOfA! - _angleVertex!).direction,
        worldPos,
      );
    }

    _currentLine!.points
      ..clear()
      ..add(MathsPadStrokePoint(start))
      ..add(MathsPadStrokePoint(endPoint));

    if (isSecondLine) {
      _angleLiveEnd = endPoint;
      _angleLiveDegrees = _angleBetween(
        _angleOtherEndOfA! - _angleVertex!,
        endPoint - _angleVertex!,
      );
    }
    _activeDrawingNotifier.value++;
  }

  void _handleAngleToolEnd() {
    if (_currentLine == null) return;
    _currentLine!.invalidateCache();
    _lines.add(_currentLine!);
    _recordAction(MathsPadAction(addedLines: [_currentLine!]));
    _finishedStrokesNotifier.value++;
    _maybeRebakeLines();

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
          MathsPadFixedAngleLabel(
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

    // Snap this joint's angle (against the previous segment) to the
    // nearest 0.5° -- but not while snapping to close the polygon, which
    // must land exactly on the first vertex regardless of angle.
    if (_polygonVertices.length >= 2 && !_polygonWillClose) {
      final vertex = _polygonVertices.last;
      final prevVertex = _polygonVertices[_polygonVertices.length - 2];
      endPoint = _snapAngleToHalfDegree(
        vertex,
        (prevVertex - vertex).direction,
        endPoint,
      );
    }

    final start = _currentLine!.points.first.offset;
    _currentLine!.points
      ..clear()
      ..add(MathsPadStrokePoint(start))
      ..add(MathsPadStrokePoint(endPoint));

    // Tracked for every segment (even the very first, which has no prior
    // segment to form an angle with yet) so the live length badge always
    // has somewhere to read its endpoint from.
    _polygonLiveEnd = endPoint;
    if (_polygonVertices.length >= 2) {
      final vertex = _polygonVertices.last;
      final prevVertex = _polygonVertices[_polygonVertices.length - 2];
      _polygonLiveDegrees = _angleBetween(
        prevVertex - vertex,
        endPoint - vertex,
      );
    }
    _activeDrawingNotifier.value++;
  }

  void _handlePolygonToolEnd() {
    if (_currentLine == null) return;
    _currentLine!.invalidateCache();
    _lines.add(_currentLine!);
    _recordAction(MathsPadAction(addedLines: [_currentLine!]));
    _finishedStrokesNotifier.value++;
    _maybeRebakeLines();

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
        MathsPadFixedAngleLabel(
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
          MathsPadFixedAngleLabel(
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
    _circleLastRawAngle = null;
    _circleSweptAngle = 0;
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
    _circleLastRawAngle = null;
    _circleSweptAngle = 0;
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
      _circleLastRawAngle = _circleStartAngle;
      _circleSweptAngle = 0;
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
      // Advance the unwrapped sweep angle by the shortest signed delta from
      // the last raw sample -- this is what lets the sweep cross the
      // -pi/pi boundary cleanly and know which direction it's turning.
      final double rawDelta = _shortestAngleDelta(_circleLastRawAngle!, angle);
      final double fromAngle = _circleStartAngle! + _circleSweptAngle;
      _circleSweptAngle += rawDelta;
      _circleLastRawAngle = angle;
      final double toAngle = _circleStartAngle! + _circleSweptAngle;

      // Densely fill in every point between the previous and new angle at a
      // fixed arc-length spacing (~1.2 world px) -- independent of how far
      // apart the two raw pointer samples actually were, so the traced arc
      // is always smooth regardless of the input device's event rate.
      final double span = toAngle - fromAngle;
      final double angularStep = (1.2 / _circleMaxRadius).clamp(0.005, 0.2);
      final int steps = (span.abs() / angularStep).floor();
      for (int i = 1; i <= steps; i++) {
        final double a = fromAngle + angularStep * i * span.sign;
        _circleArcPoints.add(
          _circleCenter! + Offset(cos(a), sin(a)) * _circleMaxRadius,
        );
      }
      final Offset tracedPoint =
          _circleCenter! +
          Offset(cos(toAngle), sin(toAngle)) * _circleMaxRadius;
      if (_circleArcPoints.isEmpty ||
          (tracedPoint - _circleArcPoints.last).distance >= 0.5) {
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
      _recordAction(MathsPadAction(addedLines: [_currentLine!]));
      _finishedStrokesNotifier.value++;
      _maybeRebakeLines();
    }
    // If the user never actually rotated, there's no arc to keep -- the
    // straight radius preview is discarded (nothing committed).
    _currentLine = null;
    _resetCircleArcTool();
  }

  // ─── Square Tool ─────────────────────────────────────────────────────────

  void _resetSquareTool() {
    _squareHoldTimer?.cancel();
    _squareHoldTimer = null;
    _squareHoldAnchor = null;
    _squareBaseStart = null;
    _squareBaseEnd = null;
    _squareSideLength = 0;
    _squareHasArmed = false;
    _squareLivePoints = [];
  }

  /// If the line from [start] to [end] is within a few degrees of exactly
  /// horizontal or vertical, snaps it to that exact axis (same length,
  /// corrected angle) so a base side that's "close enough" to level/plumb
  /// locks perfectly straight instead of the square coming out slightly
  /// skewed.
  Offset _snapToAxisIfClose(Offset start, Offset end) {
    final Offset vec = end - start;
    final double len = vec.distance;
    if (len < 1) return end;
    double angle = atan2(vec.dy, vec.dx);
    const double snapToleranceRad = 5 * pi / 180;
    const List<double> axisAngles = [0, pi / 2, pi, -pi / 2, -pi];
    for (final double target in axisAngles) {
      double diff = (angle - target).abs();
      if (diff > pi) diff = 2 * pi - diff;
      if (diff <= snapToleranceRad) {
        angle = target;
        break;
      }
    }
    return start + Offset(cos(angle), sin(angle)) * len;
  }

  void _handleSquareToolStart(Offset worldPos) {
    _squareHoldTimer?.cancel();
    _squareHoldTimer = null;
    _squareHoldAnchor = null;
    _squareBaseStart = worldPos;
    _squareBaseEnd = worldPos;
    _squareSideLength = 0;
    _squareHasArmed = false;
    _squareLivePoints = [];
    _currentLine = MathsPadLine(
      points: [MathsPadStrokePoint(worldPos)],
      color: _selectedColor,
      strokeWidth: _penWidth,
      isShape:
          true, // closed quadrilateral -- crisp straight edges, no smoothing
    );
  }

  /// Fires once the pointer has held still at [holdPos] for a full second --
  /// locks the base side's length (and direction) and arms the tool to
  /// extend a square from it. Same hold-to-arm mechanic as the Circle/Arc
  /// Tool, for the same reason: a drag that never pauses never starts a
  /// square at all.
  void _armSquareHold(Offset holdPos) {
    if (!mounted || _currentLine == null || _squareBaseStart == null) return;
    setState(() {
      _squareHasArmed = true;
      _squareBaseEnd = holdPos;
      _squareSideLength = (holdPos - _squareBaseStart!).distance;
    });
  }

  void _handleSquareToolUpdate(Offset worldPos) {
    if (_currentLine == null || _squareBaseStart == null) return;

    if (!_squareHasArmed) {
      // Still drawing the initial straight side -- track the live end so
      // the dynamic length badge always matches exactly what's on screen.
      if ((worldPos - _squareBaseStart!).distance < 1) return;
      final Offset snappedEnd = _snapToAxisIfClose(_squareBaseStart!, worldPos);
      _squareBaseEnd = snappedEnd;
      _currentLine!.points
        ..clear()
        ..add(MathsPadStrokePoint(_squareBaseStart!))
        ..add(MathsPadStrokePoint(snappedEnd));

      // Restart the 1-second hold timer whenever the pointer moves away from
      // wherever it's currently anchored -- identical logic to the Circle/
      // Arc Tool's hold-to-arm. Hold-stillness is judged against the raw
      // pointer position (not the snapped one) so snapping never resets the
      // timer by itself, but the timer fires with the snapped endpoint so
      // the armed square starts from the corrected axis-aligned side.
      const double holdTolerance = 6.0;
      if (_squareHoldAnchor == null ||
          (worldPos - _squareHoldAnchor!).distance > holdTolerance) {
        _squareHoldAnchor = worldPos;
        _squareHoldTimer?.cancel();
        final Offset anchorForThisHold = snappedEnd;
        _squareHoldTimer = Timer(
          const Duration(seconds: 1),
          () => _armSquareHold(anchorForThisHold),
        );
      }
    } else {
      // Armed: the base side's length L and direction are locked. The two
      // sides perpendicular to it grow LIVE with how far the pointer has
      // moved off the base line (like normally dragging out a rectangle),
      // but that extent is clamped to L -- so it can never overshoot into
      // a rectangle, growth just stops once it's a true square, however
      // far past that point the drag continues. The 4th side (parallel to
      // the base) is simply wherever those two growing sides currently end.
      final Offset baseStart = _squareBaseStart!;
      final Offset baseEnd = _squareBaseEnd!;
      final Offset baseVec = baseEnd - baseStart;
      if (_squareSideLength < 1) return;
      final Offset unitPerp =
          Offset(-baseVec.dy, baseVec.dx) / _squareSideLength;
      final Offset toPointer = worldPos - baseStart;
      final double signedExtent =
          toPointer.dx * unitPerp.dx + toPointer.dy * unitPerp.dy;
      final double clampedExtent = signedExtent.clamp(
        -_squareSideLength,
        _squareSideLength,
      );
      final Offset offset = unitPerp * clampedExtent;

      final Offset c1 = baseStart;
      final Offset c2 = baseEnd;
      final Offset c3 = baseEnd + offset;
      final Offset c4 = baseStart + offset;
      _squareLivePoints = [c1, c2, c3, c4, c1];

      _currentLine!.points
        ..clear()
        ..addAll(_squareLivePoints.map((p) => MathsPadStrokePoint(p)));
    }
    _activeDrawingNotifier.value++;
  }

  void _handleSquareToolEnd() {
    if (_currentLine == null) {
      _resetSquareTool();
      return;
    }
    if (_squareHasArmed && _squareLivePoints.length > 2) {
      _currentLine!.points
        ..clear()
        ..addAll(_squareLivePoints.map((p) => MathsPadStrokePoint(p)));
      _currentLine!.invalidateCache();
      _lines.add(_currentLine!);
      _recordAction(MathsPadAction(addedLines: [_currentLine!]));
      _finishedStrokesNotifier.value++;
      _maybeRebakeLines();
    }
    // If the user never actually armed it (no hold), there's no square to
    // keep -- the straight side preview is discarded (nothing committed).
    _currentLine = null;
    _resetSquareTool();
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
        _MathsPadFinishedStrokesPainter(lines: _lines);
    // `paint()` (not the old private `_drawStrokes`, since renamed/split
    // into 3 passes -- see that method's doc comments) so bucket-fill
    // boundary detection sees the exact same picture the real layers
    // render, images included.
    tempPainter.paint(
      offscreenCanvas,
      Size(width.toDouble(), height.toDouble()),
    );
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

    // "Ink" here means "meaningfully covered by a stroke," not "fully
    // opaque" -- every palette colour IS fully opaque, but a *thin* stroke
    // (e.g. 2px) can still split its antialiased coverage across 2-3 pixel
    // rows depending on exactly where it falls on the pixel grid, so no
    // single pixel along it may ever reach anywhere near 255 alpha. A
    // threshold up near 255 reads that whole stroke as "still background"
    // and the flood leaks straight through it (and keeps going through
    // whatever's next, however far that spreads). Kept low enough to
    // reliably catch even a faint thin-stroke edge; the cost is the fill
    // can stop a hair short of a thick stroke's outermost antialiased
    // pixel or two, which is imperceptible at normal zoom.
    const int solidInkAlpha = 90;

    // Like MS Paint's bucket fill: tapping empty (background) space floods
    // every pixel that isn't solidly inked yet, including the boundary
    // stroke's own antialiased/soft edge -- so the fill reaches all the way
    // up to the ink with no thin unfilled fringe left, regardless of how
    // wide that stroke's antialiasing happens to be. Tapping an already
    // solidly-coloured region (a recolour) instead matches that specific
    // colour, same as a normal paint-bucket recolour.
    final bool isBackgroundFill = targetA <= _fillColorTolerance;

    bool matchesTarget(int x, int y) {
      final int i = idx(x, y);
      return isBackgroundFill
          ? pixels[i + 3] < solidInkAlpha
          : (pixels[i] - targetR).abs() <= _fillColorTolerance &&
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
          final bool match =
              visited[(y - 1) * width + sx] == 0 && matchesTarget(sx, y - 1);
          if (match && !aboveAdded) {
            stack.add((y - 1) * width + sx);
            aboveAdded = true;
          } else if (!match) {
            aboveAdded = false;
          }
        }
        if (y < height - 1) {
          final bool match =
              visited[(y + 1) * width + sx] == 0 && matchesTarget(sx, y + 1);
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
      // Stays appended in true chronological order -- `_undo()` relies on
      // `_lines.removeLast()` picking whatever was actually added most
      // recently. Drawing this fill *beneath* the ink strokes is instead
      // handled purely at paint time (see `_drawStrokes`), so the boundary
      // stroke's own antialiasing draws on top of the fill colour there.
      _lines.add(fillLine);
      _recordAction(MathsPadAction(addedLines: [fillLine]));
    });
    _finishedStrokesNotifier.value++;
    _maybeRebakeLines();
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
        final removed = _instruments.removeAt(existingIndex);
        _recordAction(MathsPadAction(removedInstruments: [removed]));
      } else {
        final added = build(viewportCenter);
        _instruments.add(added);
        _recordAction(MathsPadAction(addedInstruments: [added]));
      }
    });
  }

  /// Embeds a video/GIF [entry] from the Asset Library onto the canvas as
  /// a `MediaEmbedState` overlay, centered at the current viewport and
  /// downscaled (never up) to the same `maxDim = 400.0` cap
  /// `_insertPastedImageBytes` uses for pasted images, for visually
  /// consistent initial sizing between the two insertion paths. Deliberately
  /// bypasses `_addInstrument` (a toggle-singleton, one-per-tool-type helper
  /// meant for the geometry instruments) -- a page can hold any number of
  /// media embeds.
  void _insertMediaEmbed(
    AssetLibraryEntry entry, {
    required bool isGif,
    required double naturalWidth,
    required double naturalHeight,
  }) {
    if (naturalWidth <= 0 || naturalHeight <= 0) return;
    const double maxDim = 400.0;
    final double scale =
        (naturalWidth > naturalHeight
                ? maxDim / naturalWidth
                : maxDim / naturalHeight)
            .clamp(0.0, 1.0);
    final viewportCenter = _screenToWorld(
      Offset(_canvasSize.width / 2, _canvasSize.height / 2),
    );
    setState(() {
      _assetLookupCache[entry.id] = entry;
      final newInstrument = MediaEmbedState(
        pivot: viewportCenter,
        assetId: entry.id,
        isGif: isGif,
        baseWidth: naturalWidth * scale,
        baseHeight: naturalHeight * scale,
      );
      _instruments.add(newInstrument);
      _recordAction(MathsPadAction(addedInstruments: [newInstrument]));
    });
  }

  /// Inserts a bundled 2D diagram [template] (triangle/circle/axes/number
  /// line, see `mathpad_template_models.dart`) as real editable strokes at
  /// the current viewport -- the template's lines/labels are authored
  /// around `Offset.zero`, so every point/position just needs shifting by
  /// the viewport center. Mirrors `_insertPastedImageBytes`'s
  /// setState/undo-clear/notify sequence.
  void _insertTemplate(MathPadTemplate template) {
    final viewportCenter = _screenToWorld(
      Offset(_canvasSize.width / 2, _canvasSize.height / 2),
    );
    final List<MathsPadLine> newLines = template.buildLines();
    for (final line in newLines) {
      for (final p in line.points) {
        p.offset += viewportCenter;
      }
    }
    final List<MathsPadTextLabel> newLabels = template.buildLabels();
    for (final label in newLabels) {
      label.position += viewportCenter;
    }
    setState(() {
      _lines.addAll(newLines);
      _textLabels.addAll(newLabels);
      _recordAction(
        MathsPadAction(addedLines: newLines, addedLabels: newLabels),
      );
    });
    for (final line in newLines) {
      _buildAndCachePath(line);
    }
    _finishedStrokesNotifier.value++;
    _maybeRebakeLines();
  }

  /// Generic removal for any instrument (geometry or media embed) -- the
  /// first actually-wired remove path in this file; Ruler/Protractor/
  /// SetSquare declare a `'remove'` handle key that nothing ever renders or
  /// acts on (dead code, left as-is -- see `MediaEmbedWidget`'s doc comment).
  void _removeInstrument(InstrumentState inst) {
    setState(() {
      _instruments.remove(inst);
      if (identical(_selectedMediaEmbed, inst)) _selectedMediaEmbed = null;
    });
  }

  /// Snaps a video embed's placeholder box to its true aspect ratio once
  /// `MediaEmbedWidget` reports the real decoded dimensions (fired at most
  /// once per embed -- see `onNaturalSizeResolved`). Recomputes
  /// `baseWidth`/`baseHeight` with the same never-upscale `maxDim = 400.0`
  /// cap `_insertMediaEmbed`/`_insertPastedImageBytes` both use, so a video
  /// snapping to its real size doesn't suddenly balloon past the size every
  /// other inserted asset is capped to. Pivot (center) and the user's
  /// current `scale` are left untouched, so this reads as the box's aspect
  /// correcting in place, not the embed jumping around or resetting any
  /// manual resize already applied.
  void _updateMediaEmbedNaturalSize(
    MediaEmbedState inst,
    double naturalWidth,
    double naturalHeight,
  ) {
    if (!_instruments.contains(inst) || naturalWidth <= 0 || naturalHeight <= 0)
      return;
    const double maxDim = 400.0;
    final double scale =
        (naturalWidth > naturalHeight
                ? maxDim / naturalWidth
                : maxDim / naturalHeight)
            .clamp(0.0, 1.0);
    setState(() {
      inst.baseWidth = naturalWidth * scale;
      inst.baseHeight = naturalHeight * scale;
    });
  }

  Future<void> _ensureAssetLookupCacheLoaded() async {
    if (kIsWeb) return;
    final entries = await _assetLibraryStorage.loadIndex();
    _assetLookupCache.addEntries(entries.map((e) => MapEntry(e.id, e)));
  }

  /// Opens the Asset Library picker sheet and routes each tab's selection
  /// into the appropriate insertion path -- Images reuse the existing
  /// `_insertPastedImageBytes` (already battle-tested for pasted images),
  /// 3D opens its own standalone viewer route (not embedded on canvas),
  /// Video/GIF embeds via `_insertMediaEmbed`, Templates via
  /// `_insertTemplate`. Lives entirely inside `_MathsPadWidgetState` (not
  /// injected via a `leadingToolbarAction`-style external param) since its
  /// behavior is intrinsically tied to this state's private methods.
  void _startRightToolbarHideTimer() {
    _rightToolbarHideTimer?.cancel();
    _rightToolbarHideTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _isRightToolbarVisible = false);
    });
  }

  void _keepRightToolbarOpen() {
    _rightToolbarHideTimer?.cancel();
    if (!_isRightToolbarVisible && mounted) {
      setState(() => _isRightToolbarVisible = true);
    }
  }

  Widget _buildAssetLibraryToolbarButton() {
    return Tooltip(
      message: 'Asset Library',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            await _ensureAssetLookupCacheLoaded();
            if (!mounted) return;
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => AssetLibraryPickerSheet(
                onImageSelected: (entry) async {
                  final bytes = await _assetLibraryStorage.readFileBytes(entry);
                  final viewportCenter = _screenToWorld(
                    Offset(_canvasSize.width / 2, _canvasSize.height / 2),
                  );
                  await _insertPastedImageBytes(bytes, viewportCenter);
                },
                onVideoOrGifSelected: (entry) async {
                  final bytes = await _assetLibraryStorage.readFileBytes(entry);
                  if (entry.kind == AssetKind.gif) {
                    final codec = await ui.instantiateImageCodec(bytes);
                    final frame = await codec.getNextFrame();
                    _insertMediaEmbed(
                      entry,
                      isGif: true,
                      naturalWidth: frame.image.width.toDouble(),
                      naturalHeight: frame.image.height.toDouble(),
                    );
                    frame.image.dispose();
                  } else {
                    // Video dimensions aren't known synchronously without
                    // decoding a frame (no lightweight probe available
                    // here) -- start at a sensible fixed 16:9 box; the
                    // generic 'resize' handle can adjust it afterwards.
                    _insertMediaEmbed(
                      entry,
                      isGif: false,
                      naturalWidth: 320,
                      naturalHeight: 180,
                    );
                  }
                },
                onTemplateSelected: _insertTemplate,
              ),
            );
          },
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _isDarkTheme ? _darkPanelColor : Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
              border: Border.all(color: context.glassBorder),
            ),
            child: const Icon(
              Icons.photo_library_outlined,
              color: Color(0xFF6366F1),
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpinnerToolbarButton() {
    return Tooltip(
      message: 'Student Spinner',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            final auth = Provider.of<AuthProvider>(context, listen: false);
            final batches = auth.profile?['batches'] as List? ?? [];
            showDialog(
              context: context,
              builder: (_) => StudentSpinnerDialog(batches: batches),
            );
          },
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _isDarkTheme ? _darkPanelColor : Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
              border: Border.all(color: context.glassBorder),
            ),
            child: const Icon(
              Icons.casino_rounded,
              color: Colors.orangeAccent,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEquationToolbarButton() {
    final bool isSelected = _toolMode == CanvasToolMode.equation;
    return Tooltip(
      message:
          'Equation Editor: tap empty space to add a LaTeX equation; tap an existing one to edit it, or drag it to move it',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() {
            _toolMode = CanvasToolMode.equation;
            _activeShapeTool = null;
            _selectedLines.clear();
          }),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF6366F1)
                  : (_isDarkTheme ? _darkPanelColor : Colors.white),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
              border: Border.all(color: context.glassBorder),
            ),
            child: Icon(
              Icons.functions_rounded,
              size: 24,
              color: isSelected ? Colors.white : _textColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGraphingToolbarButton() {
    return Tooltip(
      message: 'Graphing Plane',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _addInstrument(
            (i) => i is GraphState,
            (center) => GraphState(pivot: center),
          ),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _isDarkTheme ? _darkPanelColor : Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
              border: Border.all(color: context.glassBorder),
            ),
            child: const Icon(
              Icons.show_chart_rounded,
              color: Colors.blueAccent,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPdfExportToolbarButton() {
    return Tooltip(
      message: 'Export to PDF',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _exportToPdf,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _isDarkTheme ? _darkPanelColor : Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
              border: Border.all(color: context.glassBorder),
            ),
            child: const Icon(
              Icons.picture_as_pdf_rounded,
              color: Colors.redAccent,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  void _commitCompassArc(List<Offset> worldPoints) {
    if (worldPoints.length < 2) return;
    final arcLine = MathsPadLine(
      points: worldPoints.map((p) => MathsPadStrokePoint(p)).toList(),
      color: _selectedColor,
      strokeWidth: _penWidth,
    );
    arcLine.invalidateCache();

    _lines.add(arcLine);
    _finishedStrokesNotifier.value++;
    _maybeRebakeLines();
  }

  /// A placed text label: the text itself is IgnorePointer'd (dragging is
  /// handled centrally through the canvas's own gesture detector, same as
  /// every instrument, to avoid the nested-Positioned coordinate bug that
  /// affected per-widget drag handling elsewhere in this file); only the
  /// small remove button is a local tap target.
  Widget _buildTextLabelWidget(int index, MathsPadTextLabel label) {
    // Offset the outer Positioned up and left by the close-button overhang
    // (10 px) so the button sits inside the Stack's layout area and receives
    // hit tests correctly.  The Text itself is nudged back down/right by the
    // same amount to keep it anchored at label.position.
    const double overhang = 10;
    final bool isSelected = _selectedTextLabelIndex == index;
    return Positioned(
      left: label.position.dx - overhang,
      top: label.position.dy - overhang,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Invisible sizing box that includes the close-button area so the
          // Stack's own hit-test region covers the full widget including the
          // button that sticks above/to-the-right of the text.
          Padding(
            padding: const EdgeInsets.only(top: overhang, left: overhang),
            child: IgnorePointer(
              key: label.renderKey,
              child: label.isEquation
                  ? Math.tex(
                      label.text,
                      textStyle: TextStyle(
                        color: label.color,
                        fontSize: label.fontSize,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : Text(
                      label.text,
                      style: TextStyle(
                        color: label.color,
                        fontSize: label.fontSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
          // Close button and resize handle only show once this label has
          // been tapped -- not on every label all the time.
          if (isSelected) ...[
            Positioned(
              right: 0,
              top: 0,
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
            // Resize handle, bottom-right -- drag to scale the font size.
            // Purely visual here; the actual drag is driven by world-space
            // hit-testing in `_tryStartTextResizeHandle` (same pattern as
            // the geometry instrument handles), so it deliberately doesn't
            // carry its own GestureDetector.
            Positioned(
              right: -6,
              bottom: -6,
              child: IgnorePointer(
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1),
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
                    Icons.zoom_out_map_rounded,
                    size: 11,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
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
        (_textEditorController == null && _mathEditorController == null)) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: _textEditorWorldPos!.dx,
      top: _textEditorWorldPos!.dy - 26,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {}, // Absorb taps so they don't fall through to the canvas
        onPanDown: (_) {}, // Absorb pan/scale gestures
        child: Material(
          color: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.black.withOpacity(0.4)
                      : Colors.white.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withOpacity(0.1)
                        : Colors.black.withOpacity(0.05),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: SizedBox(
                  width: _isEquationEditorActive
                      ? 300
                      : 140, // Wider for equations
                  child: _isEquationEditorActive
                      ? DefaultTextStyle(
                          style: TextStyle(
                            color: isDark ? Colors.white : _darkPanelColor,
                            fontSize: 18,
                          ),
                          child: MathField(
                            controller: _mathEditorController!,
                            keyboardType: MathKeyboardType.expression,
                            variables: const [
                              'x',
                              'y',
                              'z',
                              'a',
                              'b',
                              'c',
                              'n',
                              'k',
                              'i',
                              't',
                              'A',
                              'B',
                              'C',
                              'f',
                            ],
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: 'Equation…',
                              hintStyle: TextStyle(
                                color: isDark ? Colors.white54 : Colors.black45,
                              ),
                            ),
                            onChanged: (String value) {
                              _currentLatexString = value;
                            },
                            onSubmitted: (String value) {
                              _currentLatexString = value;
                              _commitTextEditor();
                            },
                            autofocus: true,
                          ),
                        )
                      : TextField(
                          controller: _textEditorController,
                          autofocus: true,
                          cursorColor: isDark ? Colors.white : Colors.black87,
                          style: TextStyle(
                            color: isDark ? Colors.white : _darkPanelColor,
                            fontSize: 16,
                            letterSpacing: -0.3,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: 'Label text…',
                            hintStyle: TextStyle(
                              color: isDark ? Colors.white54 : Colors.black45,
                            ),
                          ),
                          onSubmitted: (_) => _commitTextEditor(),
                          textInputAction: TextInputAction.done,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Small floating "Paste" button shown after a ~500ms press-and-hold
  /// (see the long-press timer in _onPointerDown), the touch equivalent of
  /// Ctrl+V -- tapping it pastes from the system clipboard at that spot;
  /// tapping anywhere else just dismisses it (handled in _onScaleStart).
  Widget _buildPastePopup(bool isDark) {
    if (_pastePopupWorldPos == null) return const SizedBox.shrink();
    final Offset pos = _pastePopupWorldPos!;
    return Positioned(
      left: pos.dx,
      top: pos.dy - 26,
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            setState(() => _pastePopupWorldPos = null);
            _pasteFromSystemClipboard(atWorldPos: pos);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? _darkPanelColor : Colors.white,
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
                const Icon(
                  Icons.content_paste_rounded,
                  color: Color(0xFF6366F1),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  'Paste',
                  style: TextStyle(
                    color: isDark ? Colors.white : _darkPanelColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInstrumentWidget(InstrumentState inst) {
    final isDark = _isDarkTheme;
    if (inst is RulerState) {
      return RulerWidget(
        key: ValueKey(inst),
        state: inst,
        isDark: isDark,
        logoImage: _logoImage,
      );
    } else if (inst is ProtractorState) {
      return ProtractorWidget(
        key: ValueKey(inst),
        state: inst,
        isDark: isDark,
        logoImage: _logoImage,
      );
    } else if (inst is SetSquareState) {
      return SetSquareWidget(
        key: ValueKey(inst),
        state: inst,
        isDark: isDark,
        logoImage: _logoImage,
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
      );
    } else if (inst is MediaEmbedState) {
      return MediaEmbedWidget(
        key: ValueKey(inst),
        state: inst,
        isDark: isDark,
        isSelected: identical(_selectedMediaEmbed, inst),
        entry: _assetLookupCache[inst.assetId],
        storage: _assetLibraryStorage,
        onRemove: () => _removeInstrument(inst),
        onNaturalSizeResolved: inst.isGif
            ? null
            : (w, h) => _updateMediaEmbedNaturalSize(inst, w, h),
      );
    } else if (inst is GraphState) {
      return GraphWidget(
        key: ValueKey(inst),
        state: inst,
        onStateChanged: () {
          // Trigger a repaint when the graph equation changes
          setState(() {});
        },
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
                  : Border.all(color: _darkPanelColor.withOpacity(0.12)),
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
                color: live ? Colors.white : _darkPanelColor,
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
  /// i.e. a point inside the wedge, matching [MathsPadFixedAngleLabel.labelPosition].
  Offset _bisectorPoint(Offset vertex, double startAngle, double sweepAngle) {
    final bisector = startAngle + sweepAngle / 2;
    return vertex +
        Offset(cos(bisector), sin(bisector)) *
            MathsPadFixedAngleLabel.labelRadius;
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

  /// The Ruler's live measurement badge text while its pencil is being
  /// dragged: always the pencil's own position along the ruled edge --
  /// i.e. the actual ruler reading under the pencil, matching what a real
  /// ruler shows regardless of whether you're mid-stroke -- never the
  /// drawn line's own length.
  String _rulerLiveLengthText(RulerState ruler) {
    final double cm = ruler.pencilOffsetPx / kPxPerCm;
    return '${cm.toStringAsFixed(1)} cm';
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
  // The compass's armAngle at the moment a *hinge* drag started -- the
  // hinge point isn't on the tip's radius circle (see `hingePoint`'s
  // perpendicular "bulge" offset), so unlike the tip handle its raw
  // world position can't be mapped to a pencil angle directly. Instead the
  // hinge drag rotates the whole compass by whatever angle the pointer
  // itself has swept (relative to pivot) since the drag started, applied
  // on top of this starting angle.
  double? _instrumentDragStartArmAngle;

  // Ruler/Set Square pencil drag: the pencil's own `pencilOffsetPx` at the
  // moment the drag started, plus where THAT SAME initial touch projected
  // onto the ruled edge -- together these let the update handler apply
  // only the DELTA the touch has moved since, the same pattern the 'move'
  // handle already uses (`_instrumentDragStartPivot` + delta). Without
  // this, the pencil used to jump straight to wherever the touch currently
  // is on every drag, which is only the same place the icon started if you
  // happened to touch down on its exact center pixel -- anywhere else
  // within the handle's (deliberately generous) hit-test tolerance made it
  // visibly snap the instant the drag began.
  double? _instrumentDragStartPencilOffsetPx;
  double? _instrumentDragStartPencilProjectedPx;

  // Protractor pencil drag: same delta-preserving idea as the two fields
  // above, but for `pencilAngle` -- the pencil's starting angle, plus the
  // initial touch's own computed local angle.
  double? _instrumentDragStartPencilAngle;
  double? _instrumentDragStartPencilTouchAngle;

  Offset? _lastCompassTracePoint;
  // Tracks the compass's arc sweep as a continuously-unwrapped angle (not
  // the wrapped -pi..pi `Offset.direction` sample) so points can be
  // densely interpolated between two consecutive pointer events -- same
  // fix as the Circle/Arc Tool's sweep tracking, for the same reason (a
  // coarser input event rate otherwise leaves visible gaps that read as a
  // jagged/faceted arc instead of a smooth circle).
  double? _lastCompassRawAngle;
  double _compassCumulativeAngle = 0;
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
        final proj = _projectPointOntoSegment(
          worldPos,
          edges[i].$1,
          edges[i].$2,
        );
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
    if (inst is ProtractorState) return inst.pencilArmed;
    return false;
  }

  void _togglePencilArmed(InstrumentState inst) {
    if (inst is RulerState) inst.pencilArmed = !inst.pencilArmed;
    if (inst is SetSquareState) inst.pencilArmed = !inst.pencilArmed;
    if (inst is ProtractorState) inst.pencilArmed = !inst.pencilArmed;
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
        final onLeg = _projectPointOntoSegment(
          worldPos,
          inst.pivot,
          inst.hingePoint,
        );
        if ((onLeg - worldPos).distance <= tolerance) {
          return (inst, 'pivot');
        }
      }
      // A media embed's 'move' handle sits exactly at its pivot (center) --
      // fine as a precise grab point, but tapping anywhere else on the
      // visible video/GIF tile should drag it too, the way you'd expect to
      // pick up a sticker rather than needing to find a specific handle
      // dot. Only reached if the tap missed every handle above, so the
      // rotate/resize handles (outside the rect) still take priority.
      if (inst is MediaEmbedState) {
        final local = inst.worldToLocal(worldPos);
        if (local.dx.abs() <= inst.worldWidth / 2 &&
            local.dy.abs() <= inst.worldHeight / 2) {
          return (inst, 'move');
        }
      }
      // No dedicated 'move' handle for the Ruler/Protractor -- tapping
      // anywhere on the instrument's own body drags it directly, the same
      // "pick it up like a sticker" pattern the Media Embed above already
      // uses. Only reached if the tap missed every handle above, so the
      // rotate/resize/remove/pencil handles (outside the body) still take
      // priority.
      if (inst is RulerState) {
        final local = inst.worldToLocal(worldPos);
        final double halfLen = inst.lengthPx / 2;
        if (local.dx.abs() <= halfLen && local.dy.abs() <= kRulerHalfHeight) {
          return (inst, 'move');
        }
      }
      if (inst is ProtractorState) {
        final local = inst.worldToLocal(worldPos);
        // Matches the drawn semicircle: bulges toward local -y, flat edge
        // along local y = 0 -- so only the upper half of the full circle
        // counts as "on the body".
        if (local.dy <= 0 &&
            local.dx * local.dx + local.dy * local.dy <=
                inst.radius * inst.radius) {
          return (inst, 'move');
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
    _textLabelWasAlreadySelected = _selectedTextLabelIndex == idx;
    _draggedTextLabelIndex = idx;
    _textDragPointerStart = worldPos;
    _textDragLabelStart = _textLabels[idx].position;
    _textDragMoved = false;
    if (!_textLabelWasAlreadySelected) {
      setState(() => _selectedTextLabelIndex = idx);
    }
    return true;
  }

  /// Bottom-right resize handle -- only hit-testable while its label is
  /// already selected (matching the handle only being drawn then).
  bool _tryStartTextResizeHandle(Offset worldPos) {
    final int? idx = _selectedTextLabelIndex;
    if (idx == null || idx >= _textLabels.length) return false;
    final MathsPadTextLabel label = _textLabels[idx];
    final Offset handlePos = label.worldBounds.bottomRight;
    const double toleranceScreenPx = 16.0;
    if ((worldPos - handlePos).distance > toleranceScreenPx / _scale) {
      return false;
    }
    _resizingTextLabelIndex = idx;
    _resizeStartFontSize = label.fontSize;
    _resizeStartCornerDist = max((handlePos - label.position).distance, 1.0);
    return true;
  }

  void _updateTextResizeHandle(Offset worldPos) {
    final int? idx = _resizingTextLabelIndex;
    if (idx == null ||
        _resizeStartFontSize == null ||
        _resizeStartCornerDist == null) {
      return;
    }
    final double dist = max(
      (worldPos - _textLabels[idx].position).distance,
      1.0,
    );
    final double factor = (dist / _resizeStartCornerDist!).clamp(0.3, 6.0);
    setState(() {
      _textLabels[idx].fontSize = (_resizeStartFontSize! * factor).clamp(
        8.0,
        160.0,
      );
    });
  }

  void _endTextResizeHandle() {
    _resizingTextLabelIndex = null;
    _resizeStartFontSize = null;
    _resizeStartCornerDist = null;
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
      _textLabels[_draggedTextLabelIndex!].position =
          _textDragLabelStart! + delta;
    });
  }

  /// If the pointer never actually moved, treat it as a tap. The first tap
  /// on a label just selects it (revealing its close button and resize
  /// handle); a second tap on an already-selected label opens it for
  /// editing.
  void _endTextLabelDrag() {
    if (_draggedTextLabelIndex == null) return;
    final int idx = _draggedTextLabelIndex!;
    final bool moved = _textDragMoved;
    final bool wasAlreadySelected = _textLabelWasAlreadySelected;
    _draggedTextLabelIndex = null;
    _textDragPointerStart = null;
    _textDragLabelStart = null;
    _textDragMoved = false;
    _textLabelWasAlreadySelected = false;
    if (!moved && wasAlreadySelected) {
      _openTextEditor(editingIndex: idx);
    }
  }

  bool _isEquationEditorActive = false;

  void _openTextEditor({
    int? editingIndex,
    Offset? newPosition,
    bool isEquation = false,
  }) {
    setState(() {
      _textEditingIndex = editingIndex;
      _textEditorWorldPos = editingIndex != null
          ? _textLabels[editingIndex].position
          : newPosition;

      _isEquationEditorActive = editingIndex != null
          ? _textLabels[editingIndex].isEquation
          : isEquation;
      _currentLatexString = editingIndex != null
          ? _textLabels[editingIndex].text
          : '';

      if (_isEquationEditorActive) {
        _mathEditorController = MathFieldEditingController();
        // math_keyboard doesn't support setting initial value via constructor, but we can evaluate it if needed
        // for now we just leave it blank if editing, as math_keyboard API for arbitrary LaTeX injection is complex
        // (wait, actually, math_keyboard supports inserting LaTeX via controller or it has no initial text natively without parsing)
      } else {
        _textEditorController = TextEditingController(
          text: editingIndex != null ? _textLabels[editingIndex].text : '',
        );
      }
      _textEditorOpen = true;
    });
  }

  void _commitTextEditor() {
    if (!_textEditorOpen) return;

    // We get the raw latex from MathField or plain string from TextField
    String value = '';
    if (_isEquationEditorActive) {
      value = _currentLatexString.trim();
    } else {
      value = _textEditorController?.text.trim() ?? '';
    }

    final int? editingIndex = _textEditingIndex;
    final Offset? newPosition = _textEditorWorldPos;
    setState(() {
      if (editingIndex != null) {
        if (value.isEmpty) {
          final removedLabel = _textLabels[editingIndex];
          _textLabels.removeAt(editingIndex);
          _recordAction(MathsPadAction(removedLabels: [removedLabel]));
          if (_selectedTextLabelIndex == editingIndex) {
            _selectedTextLabelIndex = null;
          }
        } else {
          _textLabels[editingIndex].text = value;
          _selectedTextLabelIndex = editingIndex;
        }
      } else if (value.isNotEmpty && newPosition != null) {
        final newLabel = MathsPadTextLabel(
          position: newPosition,
          text: value,
          color: _selectedColor,
          isEquation: _isEquationEditorActive,
        );
        _textLabels.add(newLabel);
        _recordAction(MathsPadAction(addedLabels: [newLabel]));
        _selectedTextLabelIndex = _textLabels.length - 1;
      }

      _textEditorController?.dispose();
      _textEditorController = null;
      _mathEditorController?.dispose();
      _mathEditorController = null;

      _textEditorOpen = false;
      _textEditingIndex = null;
      _textEditorWorldPos = null;
    });
    // Reclaim focus for the canvas once the text editor is closed
    if (!_canvasFocusNode.hasFocus) {
      _canvasFocusNode.requestFocus();
    }
  }

  void _deleteTextLabel(int index) {
    setState(() {
      final removedLabel = _textLabels[index];
      _textLabels.removeAt(index);
      _recordAction(MathsPadAction(removedLabels: [removedLabel]));
      if (_selectedTextLabelIndex != null) {
        if (_selectedTextLabelIndex == index) {
          _selectedTextLabelIndex = null;
        } else if (_selectedTextLabelIndex! > index) {
          _selectedTextLabelIndex = _selectedTextLabelIndex! - 1;
        }
      }
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
    if (inst is ProtractorState)
      _instrumentDragStartRadiusOrScale = inst.radius;
    if (inst is SetSquareState) _instrumentDragStartRadiusOrScale = inst.scale;
    if (inst is MediaEmbedState) {
      _instrumentDragStartRadiusOrScale = inst.scale;
      if (!identical(_selectedMediaEmbed, inst)) {
        setState(() => _selectedMediaEmbed = inst);
      }
    }
    _instrumentDragStartPencilOffsetPx = null;
    _instrumentDragStartPencilProjectedPx = null;
    _instrumentDragStartPencilAngle = null;
    _instrumentDragStartPencilTouchAngle = null;
    if (handle == 'pencil') {
      if (inst is RulerState || inst is SetSquareState) {
        final edge = _resolvePencilEdge(inst, worldPos);
        if (edge != null) {
          final onSegment = _projectPointOntoSegment(
            worldPos,
            edge.$1,
            edge.$2,
          );
          _instrumentDragStartPencilProjectedPx =
              (onSegment - edge.$1).distance;
          _instrumentDragStartPencilOffsetPx = inst is RulerState
              ? inst.pencilOffsetPx
              : (inst as SetSquareState).pencilOffsetPx;
        }
      } else if (inst is ProtractorState) {
        final delta0 = worldPos - inst.pivot;
        final cosR0 = cos(-inst.rotation);
        final sinR0 = sin(-inst.rotation);
        _instrumentDragStartPencilTouchAngle = atan2(
          delta0.dx * sinR0 + delta0.dy * cosR0,
          delta0.dx * cosR0 - delta0.dy * sinR0,
        );
        _instrumentDragStartPencilAngle = inst.pencilAngle;
      }
    }
    if (inst is CompassState) _instrumentDragStartArmAngle = inst.armAngle;
    if (inst is CompassState &&
        (handle == 'tip' || handle == 'hinge') &&
        inst.locked) {
      inst.tracedArcPoints = [inst.tipWorldPosition];
      _lastCompassTracePoint = inst.tipWorldPosition;
      _lastCompassRawAngle = inst.armAngle;
      _compassCumulativeAngle = inst.armAngle;
    }
    return true;
  }

  /// Applies [rawAngle] (radians, already resolved by the caller -- see the
  /// 'tip' vs 'hinge' handling in `_updateInstrumentDrag`, since the two
  /// handles need different math to arrive at the pencil's actual target
  /// angle) as the compass's new arm angle, tracing a dense arc between the
  /// previous and new angle while locked. [newRadiusCm], if given, only
  /// applies while unlocked (dragging the tip itself changes the radius;
  /// dragging the hinge never should).
  void _updateCompassAngle(
    CompassState c,
    double rawAngle, {
    required bool allowRadiusChange,
    double? newRadiusCm,
  }) {
    c.armAngle = rawAngle;

    if (c.locked) {
      // Advance the unwrapped sweep angle by the shortest signed delta from
      // the last raw sample, then densely fill in every point between the
      // previous and new angle at a fixed arc-length spacing (~0.5-1.2
      // world px) -- independent of how far apart the two raw pointer
      // samples actually were, so the traced arc is always smooth
      // regardless of the input device's event rate (identical fix to the
      // Circle/Arc Tool).
      final double fromAngle = _compassCumulativeAngle;
      final double rawDelta = _shortestAngleDelta(
        _lastCompassRawAngle ?? rawAngle,
        rawAngle,
      );
      _compassCumulativeAngle += rawDelta;
      _lastCompassRawAngle = rawAngle;
      final double toAngle = _compassCumulativeAngle;

      final double span = toAngle - fromAngle;
      final double angularStep = (1.2 / c.radiusPx).clamp(0.005, 0.2);
      final int steps = (span.abs() / angularStep).floor();
      for (int i = 1; i <= steps; i++) {
        final double a = fromAngle + angularStep * i * span.sign;
        c.tracedArcPoints.add(c.pivot + Offset(cos(a), sin(a)) * c.radiusPx);
      }
      final Offset tip =
          c.pivot + Offset(cos(toAngle), sin(toAngle)) * c.radiusPx;
      if (c.tracedArcPoints.isEmpty ||
          (tip - c.tracedArcPoints.last).distance >= 0.5) {
        c.tracedArcPoints.add(tip);
      }
      _lastCompassTracePoint = tip;
    } else if (allowRadiusChange && newRadiusCm != null) {
      c.radiusCm = newRadiusCm.clamp(0.5, 30.0);
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
        // The hinge point isn't on the tip's radius circle (it bulges off
        // to the side of the pivot-tip line -- see `hingePoint`), so its
        // raw position can't be read as the pencil's angle directly like
        // the tip's can. Instead rotate the whole compass by however much
        // the pointer itself has swept around the pivot since the drag
        // started, applied on top of the arm angle it started at -- this
        // is what keeps the pencil tracking accurately from wherever it
        // actually was, instead of snapping to whatever raw angle the
        // hinge's own position happens to sit at.
        final startVec =
            _instrumentDragStartWorld! - _instrumentDragStartPivot!;
        final currentVec = worldPos - inst.pivot;
        if (currentVec.distance >= 1) {
          final double angleDelta = _signedAngleDiff(
            startVec.direction,
            currentVec.direction,
          );
          _updateCompassAngle(
            inst,
            _instrumentDragStartArmAngle! + angleDelta,
            allowRadiusChange: false,
          );
        }
      } else if (inst is CompassState && handle == 'tip') {
        final vector = worldPos - inst.pivot;
        if (vector.distance >= 1) {
          _updateCompassAngle(
            inst,
            vector.direction,
            allowRadiusChange: !inst.locked,
            newRadiusCm: vector.distance / kPxPerCm,
          );
        }
      } else if (handle == 'move') {
        final delta = worldPos - _instrumentDragStartWorld!;
        inst.pivot = _instrumentDragStartPivot! + delta;
      } else if (handle == 'rotate') {
        final startVec =
            _instrumentDragStartWorld! - _instrumentDragStartPivot!;
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
            inst.radius = (_instrumentDragStartRadiusOrScale! * factor).clamp(
              50.0,
              400.0,
            );
          } else if (inst is SetSquareState) {
            inst.scale = (_instrumentDragStartRadiusOrScale! * factor).clamp(
              0.4,
              3.0,
            );
          } else if (inst is MediaEmbedState) {
            inst.scale = (_instrumentDragStartRadiusOrScale! * factor).clamp(
              0.2,
              4.0,
            );
          }
        }
      } else if (handle == 'pencil') {
        if (inst is ProtractorState) {
          final delta = worldPos - inst.pivot;
          final cosR = cos(-inst.rotation);
          final sinR = sin(-inst.rotation);
          final localX = delta.dx * cosR - delta.dy * sinR;
          final localY = delta.dx * sinR + delta.dy * cosR;
          final double currentTouchAngle = atan2(localY, localX);

          // Applies only the DELTA the touch's own angle has swept since
          // the drag started, on top of wherever the pencil actually was --
          // not the touch's raw current angle directly, which snapped the
          // pencil straight to the touch position the instant a drag began
          // unless you happened to grab its exact center pixel.
          double angle;
          if (_instrumentDragStartPencilTouchAngle != null &&
              _instrumentDragStartPencilAngle != null) {
            final double angleDelta = _shortestAngleDelta(
              _instrumentDragStartPencilTouchAngle!,
              currentTouchAngle,
            );
            angle = _instrumentDragStartPencilAngle! + angleDelta;
          } else {
            angle = currentTouchAngle;
          }
          // Constrain to the upper semicircle (y <= 0), i.e. 0 to -pi.
          angle = angle.clamp(-pi, 0.0);
          // Snaps to whole-degree marks -- the same integer ticks printed
          // on the protractor's own face (see `_ProtractorPainter`'s
          // `for (int deg = 0; deg <= 180; deg++)` loop) -- instead of a
          // continuous angle, so dragging the pencil lands exactly on 26°,
          // 27°, 28°, ... like moving between the printed lines one at a
          // time, never stopping at a fractional value in between.
          final double snappedDeg = ((angle + pi) * 180 / pi).roundToDouble();
          angle = (snappedDeg * pi / 180 - pi).clamp(-pi, 0.0);
          inst.pencilAngle = angle;

          final movedDist = (worldPos - _instrumentDragStartWorld!).distance;
          if (movedDist > 6) {
            _pencilDragMoved = true;
            if (_isPencilArmed(inst)) {
              final edgeWorldPos =
                  inst.pivot +
                  Offset(
                    inst.radius * cos(angle + inst.rotation),
                    inst.radius * sin(angle + inst.rotation),
                  );

              if (_currentLine == null) {
                _currentLine = MathsPadLine(
                  points: [MathsPadStrokePoint(edgeWorldPos)],
                  color: _selectedColor,
                  strokeWidth: _penWidth,
                );
              } else {
                _currentLine!.points.add(MathsPadStrokePoint(edgeWorldPos));
              }
              _activeDrawingNotifier.value++;
            }
          }
          return;
        }

        // The attached drawing pencil: a plain tap (no real movement) arms
        // it (turns blue); dragging it -- armed or not -- slides it along
        // the instrument's ruled edge (for a Set Square, whichever of its
        // three edges is currently closest), and while armed that same
        // drag also draws a straight line snapped to the edge's exact
        // angle.
        final edge = _resolvePencilEdge(inst, worldPos);
        if (edge != null) {
          final Offset edgeVector = edge.$2 - edge.$1;
          final double edgeLength = edgeVector.distance;
          final Offset edgeUnit = edgeLength > 0
              ? edgeVector / edgeLength
              : const Offset(1, 0);

          final onSegment = _projectPointOntoSegment(
            worldPos,
            edge.$1,
            edge.$2,
          );
          final distFromEdgeStart = (onSegment - edge.$1).distance;
          // Applies only the DELTA the touch has moved along the edge
          // since the drag started, on top of wherever the pencil actually
          // was -- not the touch's raw current projected position
          // directly, which snapped the pencil straight there the instant
          // a drag began unless you happened to grab its exact center
          // pixel (the handle's own hit-test tolerance is a generous 26px,
          // so that was the common case, not a rare one).
          final double newOffsetPx =
              (_instrumentDragStartPencilProjectedPx != null &&
                  _instrumentDragStartPencilOffsetPx != null)
              ? _instrumentDragStartPencilOffsetPx! +
                    (distFromEdgeStart - _instrumentDragStartPencilProjectedPx!)
              : distFromEdgeStart;
          if (inst is RulerState) inst.pencilOffsetPx = newOffsetPx;
          if (inst is SetSquareState) inst.pencilOffsetPx = newOffsetPx;

          final movedDist = (worldPos - _instrumentDragStartWorld!).distance;
          if (movedDist > 6) {
            _pencilDragMoved = true;
            if (_isPencilArmed(inst)) {
              if (_currentLine == null) {
                // Starts exactly where the pencil itself was sitting when
                // this drag began (its own `pencilOffsetPx` at that
                // moment), not wherever the touch happened to land --
                // otherwise the drawn line's start could sit visibly apart
                // from the pencil icon whenever the touch-down wasn't
                // exactly on its center pixel.
                final double startOffsetPx =
                    _instrumentDragStartPencilOffsetPx ?? distFromEdgeStart;
                final Offset start = edge.$1 + edgeUnit * startOffsetPx;
                _snappedEdgeStart = start;
                _currentLine = MathsPadLine(
                  points: [MathsPadStrokePoint(start)],
                  color: _selectedColor,
                  strokeWidth: _penWidth,
                );
              }
              // Ends exactly at the pencil's current rendered position --
              // the same `newOffsetPx` the icon itself is drawn at -- so
              // the drawn line always tracks/follows the visible pencil,
              // instead of the raw touch position which can now differ
              // from it (see `newOffsetPx`'s own doc comment above).
              final Offset end = edge.$1 + edgeUnit * newOffsetPx;
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

    if (inst is CompassState &&
        inst.locked &&
        inst.tracedArcPoints.length > 1) {
      _commitCompassArc(List<Offset>.from(inst.tracedArcPoints));
    }
    if (inst is CompassState) {
      inst.tracedArcPoints = [];
    }

    if (inst != null && handle == 'pencil') {
      if (!_pencilDragMoved) {
        _togglePencilArmed(inst);
        if (inst is ProtractorState) {
          final edgeWorldPos =
              inst.pivot +
              Offset(
                inst.radius * cos(inst.pencilAngle + inst.rotation),
                inst.radius * sin(inst.pencilAngle + inst.rotation),
              );
          final dot = MathsPadLine(
            points: [
              MathsPadStrokePoint(edgeWorldPos),
              MathsPadStrokePoint(edgeWorldPos + const Offset(0.1, 0.1)),
            ],
            color: _selectedColor,
            strokeWidth: _penWidth * 1.5,
          );
          _lines.add(dot);
          _recordAction(MathsPadAction(addedLines: [dot]));
          _finishedStrokesNotifier.value++;
          _maybeRebakeLines();
        }
      } else if (_currentLine != null) {
        _currentLine!.invalidateCache();
        _lines.add(_currentLine!);
        _recordAction(MathsPadAction(addedLines: [_currentLine!]));
        _finishedStrokesNotifier.value++;
        _maybeRebakeLines();
        _currentLine = null;
      }
    }

    setState(() {
      _draggedInstrument = null;
      _draggedHandle = null;
      _lastCompassTracePoint = null;
      _lastCompassRawAngle = null;
      _compassCumulativeAngle = 0;
      _snappedEdgeStart = null;
      _pencilDragMoved = false;
      _instrumentDragStartPencilOffsetPx = null;
      _instrumentDragStartPencilProjectedPx = null;
      _instrumentDragStartPencilAngle = null;
      _instrumentDragStartPencilTouchAngle = null;
    });
  }

  // Calculate Group Bounding Box Rect for active selection
  /// The single selected image's rotation, when there's exactly one line
  /// selected and it's an image (Fill Tool result or pasted image) --
  /// otherwise 0. The selection box/handles are drawn and hit-tested
  /// rotated by this amount so they visually track the image instead of
  /// staying axis-aligned while only the image itself spins (freehand
  /// strokes don't need this: their own points already rotate in place, so
  /// their bounds naturally follow).
  double get _selectedImageRotation {
    if (_selectedLines.length == 1) {
      final line = _selectedLines.first;
      if (line.fillImage != null) return line.rotation;
    }
    return 0;
  }

  Offset _rotatePointAround(Offset point, Offset center, double angle) {
    if (angle == 0) return point;
    final double cosA = cos(angle);
    final double sinA = sin(angle);
    final Offset local = point - center;
    return center +
        Offset(
          local.dx * cosA - local.dy * sinA,
          local.dx * sinA + local.dy * cosA,
        );
  }

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

  // Hit-test selection controls (Rotation Handle, 4 Corner Resize Handles, Move Area).
  // [selectionRotation] un-rotates [worldPos] into the box's own local
  // (unrotated) frame first, so handles that are drawn rotated (see
  // `_drawSelectionOverlay`) are still grabbable where they visually are.
  SelectionHandleType _hitTestSelectionHandles(
    Offset worldPos,
    Rect bounds, [
    double selectionRotation = 0,
  ]) {
    worldPos = _rotatePointAround(worldPos, bounds.center, -selectionRotation);
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

  // Find drawn stroke line closest to tapped world position. [includeImages]
  // defaults true for normal tap-select/lasso use; the Eraser tool passes
  // false so it can never hit (and delete) an image -- see
  // `_findImageLineAt`'s doc comment for why images need their own
  // proper rectangular hit-test anyway, separate from this one.
  MathsPadLine? _findLineAt(Offset worldPos, {bool includeImages = true}) {
    for (int i = _lines.length - 1; i >= 0; i--) {
      final line = _lines[i];
      if (line.isEraser) continue;
      if (!includeImages && line.fillImage != null) continue;
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

  /// Proper rectangular (rotation-aware) hit-test for image-backed lines
  /// (`fillImage`) -- unlike `_findLineAt`, which treats every line as a
  /// thin polyline path: for an image, whose `points` are just its two
  /// opposite corners, that only ever hits the thin diagonal between
  /// them, not the image's actual visible area. Used by the
  /// double-tap-to-select-image gesture (see `_onPointerDown`), which
  /// needs to hit anywhere within the image regardless of which tool is
  /// currently active. Only considers pasted images, not Fill Tool
  /// results -- double-tapping a flood-fill patch isn't a meaningful
  /// "select this image" gesture the way it is for something you pasted.
  MathsPadLine? _findImageLineAt(Offset worldPos) {
    for (int i = _lines.length - 1; i >= 0; i--) {
      final line = _lines[i];
      if (!line.isPastedImage ||
          line.fillImage == null ||
          line.fillWorldBounds == null) {
        continue;
      }
      Offset testPos = worldPos;
      if (line.rotation != 0) {
        // Undo the image's own rotation around its center so the test
        // can stay a simple axis-aligned rect check.
        final Offset center = line.fillWorldBounds!.center;
        final Offset rel = worldPos - center;
        final double cosA = cos(-line.rotation);
        final double sinA = sin(-line.rotation);
        testPos =
            Offset(
              rel.dx * cosA - rel.dy * sinA,
              rel.dx * sinA + rel.dy * cosA,
            ) +
            center;
      }
      if (line.fillWorldBounds!.contains(testPos)) {
        return line;
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

    // Track the eraser ring position even during hover so the custom
    // cursor is visible when the system cursor is hidden.
    if (_toolMode == CanvasToolMode.eraser || _isStylusBarrelPressed) {
      if (_eraserCursorPos != newWorldPos) {
        _eraserCursorPos = newWorldPos;
        _activeDrawingNotifier.value++;
      }
    } else if (_eraserCursorPos != null) {
      _eraserCursorPos = null;
      _activeDrawingNotifier.value++;
    }
  }

  void _updateStylusBarrelState(PointerEvent event) {
    final bool isPrimaryBarrel =
        event.kind == PointerDeviceKind.invertedStylus ||
        (event.buttons & kSecondaryButton != 0);
    final bool isSecondaryBarrel = (event.buttons & kTertiaryButton != 0);
    final bool isBarrelOrInverted = isPrimaryBarrel;

    if (_isStylusBarrelPressed != isBarrelOrInverted) {
      setState(() {
        _isStylusBarrelPressed = isBarrelOrInverted;
      });
    }

    if (_isPrimaryBarrelPressed != isPrimaryBarrel) {
      _isPrimaryBarrelPressed = isPrimaryBarrel;
      if (isPrimaryBarrel) {
        final now = DateTime.now();
        if (_lastPrimaryBarrelPressTime != null &&
            now.difference(_lastPrimaryBarrelPressTime!) <= _kDoubleTapMaxGap) {
          if (_toolMode != CanvasToolMode.pen) {
            setState(() {
              _toolMode = CanvasToolMode.pen;
              _activeShapeTool = null;
              _selectedLines.clear();
            });
          }
          _lastPrimaryBarrelPressTime = null;
        } else {
          _lastPrimaryBarrelPressTime = now;
        }
      }
    }

    if (_isSecondaryBarrelPressed != isSecondaryBarrel) {
      _isSecondaryBarrelPressed = isSecondaryBarrel;
      if (isSecondaryBarrel) {
        final now = DateTime.now();
        if (_lastSecondaryBarrelPressTime != null &&
            now.difference(_lastSecondaryBarrelPressTime!) <=
                _kDoubleTapMaxGap) {
          if (_toolMode != CanvasToolMode.tapSelect) {
            setState(() {
              _toolMode = CanvasToolMode.tapSelect;
              _activeShapeTool = null;
            });
          }
          _lastSecondaryBarrelPressTime = null;
        } else {
          _lastSecondaryBarrelPressTime = now;
        }
      }
    }
  }

  void _onPointerHover(PointerHoverEvent event) {
    _updatePointerPos(event.localPosition);
    _updateStylusBarrelState(event);
  }

  void _onPointerDown(PointerDownEvent event) {
    // Reclaim keyboard focus for the canvas on every single touch/click
    // down on it -- without this, focus stays wherever it last landed
    // (e.g. a toolbar `IconButton`/`ElevatedButton`, which Flutter gives
    // focus to on tap by default), so Ctrl+Z/Ctrl+Y and the other
    // keyboard shortcuts in this widget's `Focus.onKeyEvent` silently
    // stop reaching it at all -- not a bug in `_undo()` itself, which
    // never sees the key event to begin with. This is exactly what made
    // undo look broken right after drawing a very first stroke (the
    // canvas's own `autofocus` hadn't necessarily settled yet) or right
    // after inserting a pasted image (see `_insertPastedImageBytes`,
    // which reaches this same fix via its own explicit
    // `_canvasFocusNode.requestFocus()` since pasting doesn't always
    // involve a fresh pointer-down on the canvas itself).
    // Note: We MUST NOT steal focus if the text editor is open, otherwise
    // tapping inside the text editor's field will immediately dismiss its cursor!
    if (!_textEditorOpen && !_canvasFocusNode.hasFocus) {
      _canvasFocusNode.requestFocus();
    }
    if (_isFullScreenMode && _toolbarRevealedInFullScreen) {
      setState(() {
        _toolbarRevealedInFullScreen = false;
        widget.onCanvasOnlyModeChanged?.call(true);
      });
    }
    _frictionController?.stop();
    _updatePointerPos(event.localPosition);
    _activePointers[event.pointer] = event.localPosition;
    _lastCentroid = _calculateCentroid();
    _currentPointerPressure = event.pressure;
    _capturePencilStylusPressure(event);

    // Double-tap-to-select-image tracking -- compare THIS down against
    // the PREVIOUS one (recorded last time) before overwriting it, so
    // `_onScaleStart` (which runs right after this, for the same touch)
    // can just read `_isDoubleTapPointerDown` to know whether to select
    // an image instead of starting a normal draw/tool action. See the
    // field's doc comment for why this lives here rather than
    // `GestureDetector.onDoubleTap`.
    if (_activePointers.length == 1) {
      final DateTime now = DateTime.now();
      final DateTime? prevTime = _lastPointerDownTime;
      final Offset? prevPos = _lastPointerDownScreenPos;
      _isDoubleTapPointerDown =
          prevTime != null &&
          prevPos != null &&
          now.difference(prevTime) <= _kDoubleTapMaxGap &&
          (event.localPosition - prevPos).distance <= _kDoubleTapMaxDistance;
      _lastPointerDownTime = now;
      _lastPointerDownScreenPos = event.localPosition;
    } else {
      _isDoubleTapPointerDown = false;
      _lastPointerDownTime = null;
      _lastPointerDownScreenPos = null;
    }

    // Dismiss the right toolbar if the user touches the canvas (and it's currently visible)
    // but only if they didn't touch the toolbar itself (which is handled by its own Listener).
    if (_isRightToolbarVisible) {
      _rightToolbarHideTimer?.cancel();
      setState(() => _isRightToolbarVisible = false);
    }

    // Arm the long-press-to-paste timer for a single-finger press. If a
    // second pointer joins (2-finger pan) or the finger moves too far
    // before the timer fires, it gets cancelled in _onPointerMove below.
    // Android only -- every other platform either has a real keyboard
    // (Ctrl+V) or, on iOS, its own native text/long-press paste affordance
    // that this would just duplicate/conflict with.
    if (!kIsWeb && Platform.isAndroid && _activePointers.length == 1) {
      _longPressPasteDownScreenPos = event.localPosition;
      _longPressPasteTimer?.cancel();
      _longPressPasteTimer = Timer(const Duration(milliseconds: 500), () {
        if (!mounted || _longPressPasteDownScreenPos == null) return;
        setState(() {
          _pastePopupWorldPos = _screenToWorld(_longPressPasteDownScreenPos!);
        });
      });
    }

    _updateStylusBarrelState(event);
  }

  void _onPointerMove(PointerMoveEvent event) {
    _updatePointerPos(event.localPosition);
    _currentPointerPressure = event.pressure;
    _capturePencilStylusPressure(event);

    if (_longPressPasteTimer != null && _longPressPasteDownScreenPos != null) {
      const double moveTolerance = 10.0;
      if ((event.localPosition - _longPressPasteDownScreenPos!).distance >
          moveTolerance) {
        _longPressPasteTimer?.cancel();
        _longPressPasteTimer = null;
        _longPressPasteDownScreenPos = null;
      }
    }

    if (_activePointers.containsKey(event.pointer)) {
      _activePointers[event.pointer] = event.localPosition;

      // Chrome Web Multi-Touch 2-finger pan -- web-only fallback for a past
      // Flutter Web limitation where `GestureDetector`'s own multi-touch
      // `ScaleGestureRecognizer` (wired to `_onScaleUpdate`) didn't reliably
      // recognize multi-touch trackpad/touch gestures. This branch does its
      // own scale-AGNOSTIC centroid-only panning -- previously unconditional
      // on `_activePointers.length >= 2` with no `kIsWeb` guard, so it also
      // fired on every native platform (including Windows) during an actual
      // pinch, fighting `_onScaleUpdate`'s focal-point-anchored zoom math
      // every frame and overwriting it with plain panning -- this was the
      // real reason "pinch-zoom to the exact focal point" kept failing even
      // after `_onScaleUpdate` was fixed. Gate it to web only so native
      // platforms rely purely on the correct `_onScaleUpdate` path.
      if (kIsWeb && _activePointers.length >= 2) {
        _longPressPasteTimer?.cancel();
        _longPressPasteTimer = null;
        _longPressPasteDownScreenPos = null;
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
          _panOffset = _clampPanIfLocked(_panOffset + delta);
          _panNotifier.value = _panOffset;
          _lastCentroid = currentCentroid;
        } else {
          _lastCentroid = _calculateCentroid();
        }
        return;
      }
    }

    _updateStylusBarrelState(event);
  }

  void _onPointerUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);
    if (_activePointers.isEmpty) {
      _lastCentroid = null;
    }
    // Only cancels the pending timer if it hasn't fired yet -- if the paste
    // popup is already showing, releasing the finger that triggered it
    // should NOT dismiss it (the user still needs to tap "Paste" on it).
    _longPressPasteTimer?.cancel();
    _longPressPasteTimer = null;
    _longPressPasteDownScreenPos = null;

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
    _longPressPasteTimer?.cancel();
    _longPressPasteTimer = null;
    _longPressPasteDownScreenPos = null;
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
        // Pinch-to-zoom on Chrome trackpad or Ctrl + Wheel -- direct
        // notifier update, no `setState` (see `_zoomIn`/`_zoomOut`'s doc
        // comment: a full widget-tree rebuild on every scroll tick was
        // real, avoidable cost, and this branch previously didn't even
        // update `_scaleNotifier.value` here, relying entirely on the
        // `setState` rebuild to propagate the new `_scale` to anything
        // that happened to read it -- nothing in `build()` actually does,
        // so that's fixed here too, not just the performance). This branch
        // is very likely the ACTUAL path a Windows precision-touchpad pinch
        // routes through (its own original comment: "Pinch-to-zoom on
        // Chrome trackpad or Ctrl + Wheel") -- it previously only touched
        // `_scale`, never `_panOffset`, so zooming here always drifted
        // around the canvas's pan origin instead of staying anchored under
        // the pointer. Same focal-point-anchor fix as `_onScaleUpdate`,
        // just using the pointer's current position (there's no persisted
        // gesture-start focal point for a discrete scroll/pinch tick).
        if (!_zoomLocked) {
          final Offset worldFocal = _screenToWorld(event.localPosition);
          final double zoomFactor = event.scrollDelta.dy > 0 ? 0.93 : 1.07;
          _scale = (_scale * zoomFactor).clamp(0.25, 4.0);
          _scaleNotifier.value = _scale;
          _panOffset = _clampPanIfLocked(
            event.localPosition - worldFocal * _scale,
          );
          _panNotifier.value = _panOffset;
        }
      } else {
        // Butter-smooth 1.35x 360-degree trackpad pan – direct notifier, 0 rebuilds!
        final Offset delta =
            Offset(-event.scrollDelta.dx, -event.scrollDelta.dy) * 1.35;
        _panOffset = _clampPanIfLocked(_panOffset + delta);
        _panNotifier.value = _panOffset;
      }
    }
  }

  /// Trackpad-driven pan/zoom start -- captures the same gesture-start
  /// snapshot `_onScaleStart` does, but from the raw event, and marks
  /// `_isPanZoomGestureActive` so `_onScaleUpdate`'s auto-synthesized calls
  /// for this same gesture stand down (see its doc comment).
  void _onTrackpadPanZoomStart(PointerPanZoomStartEvent event) {
    _isPanZoomGestureActive = true;
    _frictionController?.stop();
    // Tracks `event.scale`/`event.pan` from the PREVIOUS update (identity
    // at gesture start), so `_onTrackpadPanZoomUpdate` can work with
    // INCREMENTAL, frame-to-frame deltas instead of the accumulated-since-
    // start values.
    _lastPanZoomScale = 1.0;
    _lastPanZoomPan = Offset.zero;
  }

  /// Trackpad-driven pan/zoom update. `event.localPosition` is confirmed
  /// (via a live diagnostic capture) to stay exactly fixed at the cursor
  /// position for a stationary trackpad pinch -- the one genuinely
  /// reliable anchor point available for zoom. `event.pan` looked at first
  /// like a natural translation to combine with it, but it turns out to be
  /// the SAME quantity `ScaleGestureRecognizer` uses internally to
  /// synthesize its own (confirmed drifting) `localFocalPoint` --
  /// `localPosition + pan` -- so using it to relocate the zoom anchor just
  /// reproduced the identical bug through a different path; a stationary
  /// pinch reports a large, growing `pan` that's an artifact of the pinch
  /// motion itself, not real drag intent.
  ///
  /// A genuine 2-finger PAN (no pinch) is the other case this same event
  /// stream carries, and there `event.pan`'s per-frame delta IS the real,
  /// reliable signal (confirmed: `event.scale` stays exactly `1.0` frame
  /// to frame for a pure drag, only actually changing once real pinching
  /// starts) -- so route on whether THIS frame's scale actually changed:
  /// no scale change this frame -> pure pan, trust `event.pan`'s delta;
  /// scale changed -> pinch, anchor to the stable cursor position and
  /// ignore `event.pan` entirely, exactly as before.
  ///
  /// Zooming genuinely costs more than panning to actually render (scaling
  /// forces anti-aliased stroke edges to be recomputed for the new pixel
  /// density; panning can just reuse what's already there), and a fast
  /// trackpad pinch can report raw samples far faster than the display can
  /// keep up with -- pushing every single one straight to `_scaleNotifier`
  /// queues up more re-render work than the GPU can drain in real time.
  /// `_scale`/`_panOffset` themselves are still updated every call (cheap,
  /// no rendering cost), but the NOTIFIERS -- the thing that actually
  /// triggers a new frame -- are only pushed at most once per
  /// `_kPanZoomNotifyInterval`, coalescing a burst of raw samples into far
  /// fewer actual render passes. `_onTrackpadPanZoomEnd` flushes the final
  /// value so the view never ends a gesture visually stuck mid-throttle.
  void _onTrackpadPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (widget.isTransparentBg) return;
    final double incrementalScale = event.scale / _lastPanZoomScale;
    final Offset panDelta = event.pan - _lastPanZoomPan;
    _lastPanZoomScale = event.scale;
    _lastPanZoomPan = event.pan;

    if (!_zoomLocked && (incrementalScale - 1.0).abs() > 0.0001) {
      final double newScale = (_scale * incrementalScale).clamp(0.25, 4.0);
      final Offset worldFocal = (event.localPosition - _panOffset) / _scale;
      _scale = newScale;
      _panOffset = _clampPanIfLocked(event.localPosition - worldFocal * _scale);
    } else {
      _panOffset = _clampPanIfLocked(_panOffset + panDelta);
    }

    final DateTime now = DateTime.now();
    if (_lastPanZoomNotifyTime == null ||
        now.difference(_lastPanZoomNotifyTime!) >= _kPanZoomNotifyInterval) {
      _lastPanZoomNotifyTime = now;
      _scaleNotifier.value = _scale;
      _panNotifier.value = _panOffset;
    }
  }

  void _onTrackpadPanZoomEnd(PointerPanZoomEndEvent event) {
    _isPanZoomGestureActive = false;
    _lastPanZoomNotifyTime = null;
    // Flush the final scale/pan in case the throttle above deferred the
    // very last update -- otherwise the view could end a fast gesture
    // visibly a frame or two behind where your fingers actually ended up.
    _scaleNotifier.value = _scale;
    _panNotifier.value = _panOffset;
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

      // Any tap elsewhere while the long-press paste popup is showing just
      // dismisses it (tapping the popup's own "Paste" button itself never
      // reaches here -- that button consumes its own tap).
      if (_pastePopupWorldPos != null) {
        setState(() => _pastePopupWorldPos = null);
        return;
      }

      // Tapping the canvas while the full-screen quick-tools box is open
      // collapses the box, but we don't return here so that the tap
      // ALSO acts as a drawing/tool action (no need to tap twice).
      if (_quickToolsExpanded) {
        setState(() => _quickToolsExpanded = false);
      }

      // Double-tap on an image selects it, no matter which tool is
      // currently active -- checked before all the per-tool branching
      // below so it truly overrides everything, same as the laser
      // pointer/instrument-handle checks that follow. Once selected, the
      // existing selection-handle hit-test just below (unconditional on
      // `_toolMode`) already lets it be moved/resized/rotated regardless
      // of tool, so nothing else needs to change to make that work. See
      // `_isDoubleTapPointerDown`'s doc comment for how this is detected.
      if (_isDoubleTapPointerDown) {
        _isDoubleTapPointerDown = false;
        final MathsPadLine? hitImage = _findImageLineAt(worldPos);
        if (hitImage != null) {
          setState(() {
            // Same groupId-based expansion the `tapSelect` tool's own
            // tap-to-select already does -- an image "stuck" to some ink
            // (see `_toggleStickDrawingsToImage`) should select (and so
            // move/rotate together with) that ink here too, not just the
            // image alone.
            final Set<MathsPadLine> group = hitImage.groupId != null
                ? _lines.where((l) => l.groupId == hitImage.groupId).toSet()
                : {hitImage};
            _selectedLines
              ..clear()
              ..addAll(group);
            _lassoPoints.clear();
            // Also switch to the Select tool itself, so the just-selected
            // image can immediately be moved/resized/rotated by dragging
            // it directly, without an extra manual tool switch -- see
            // `_toolModeBeforeDoubleTapImageSelect`'s doc comment. Only
            // remember the PREVIOUS tool the first time (not if already
            // in Select, e.g. double-tapping a second image without
            // deselecting first), so it's the original tool -- not
            // Select itself -- that gets restored later.
            if (_toolMode != CanvasToolMode.tapSelect) {
              _toolModeBeforeDoubleTapImageSelect = _toolMode;
              _toolMode = CanvasToolMode.tapSelect;
            }
          });
          return;
        }
        // Double-tapped somewhere that isn't an image -- fall through to
        // whatever this tool would normally do with a tap here.
      }

      // Laser Pointer: purely a pointing aid, never touches instruments,
      // strokes, or selection -- handled before any of those so it can
      // point AT them without accidentally grabbing/dragging one.
      if (_toolMode == CanvasToolMode.laser) {
        _addLaserPoint(worldPos);
        return;
      }

      // Geometry instrument handles (move/rotate/resize, or the compass's
      // pivot/hinge/tip) always take priority over the current drawing
      // tool, so instruments stay adjustable no matter what's selected.
      if (_tryStartInstrumentDrag(worldPos)) {
        return;
      }

      // A selected label's resize handle takes priority over starting a
      // plain drag on it.
      if (_tryStartTextResizeHandle(worldPos)) {
        return;
      }

      // Existing text labels are always draggable/editable too, regardless
      // of the active tool -- same priority as instruments.
      if (_tryStartTextLabelDrag(worldPos)) {
        return;
      }

      // Tapped anywhere else -- deselect whichever label's close
      // button/resize handle was showing.
      if (_selectedTextLabelIndex != null) {
        setState(() => _selectedTextLabelIndex = null);
      }
      if (_selectedMediaEmbed != null) {
        setState(() => _selectedMediaEmbed = null);
      }

      if (_toolMode == CanvasToolMode.text ||
          _toolMode == CanvasToolMode.equation) {
        _openTextEditor(
          newPosition: worldPos,
          isEquation: _toolMode == CanvasToolMode.equation,
        );
        return;
      }

      if (_toolMode == CanvasToolMode.straightLine) {
        _handleStraightLineToolStart(worldPos);

        _selectedLines.clear();
        _activeDrawingNotifier.value++;
        return;
      }

      if (_toolMode == CanvasToolMode.spacer) {
        _handleSpacerToolStart(worldPos);

        _selectedLines.clear();
        return;
      }

      if (_toolMode == CanvasToolMode.angle) {
        _handleAngleToolStart(worldPos);

        _selectedLines.clear();
        _activeDrawingNotifier.value++;
        return;
      }

      if (_toolMode == CanvasToolMode.polygonAngle) {
        _handlePolygonToolStart(worldPos);

        _selectedLines.clear();
        _activeDrawingNotifier.value++;
        return;
      }

      if (_toolMode == CanvasToolMode.circleArc) {
        _handleCircleArcToolStart(worldPos);

        _selectedLines.clear();
        _activeDrawingNotifier.value++;
        return;
      }

      if (_toolMode == CanvasToolMode.square) {
        _handleSquareToolStart(worldPos);

        _selectedLines.clear();
        _activeDrawingNotifier.value++;
        return;
      }

      if (_toolMode == CanvasToolMode.fill) {
        // A tap-and-release action, not a drag -- handled entirely here.

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
        final double selRotation = _selectedImageRotation;
        final handle = _hitTestSelectionHandles(
          worldPos,
          selectionBounds,
          selRotation,
        );
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
            final Offset localWorldPos = _rotatePointAround(
              worldPos,
              selectionBounds.center,
              -selRotation,
            );
            _initialScaleDist = (localWorldPos - anchor).distance;
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
            final group = hitLine.groupId != null
                ? _lines.where((l) => l.groupId == hitLine.groupId).toSet()
                : {hitLine};
            if (_selectedLines.contains(hitLine)) {
              _selectedLines.removeAll(group);
            } else {
              _selectedLines.addAll(group);
            }
          } else {
            _selectedLines.clear();
            // Tapping empty canvas to deselect is also the trigger to
            // leave the Select tool, if it was only entered automatically
            // by double-tapping an image -- see
            // `_toolModeBeforeDoubleTapImageSelect`'s doc comment.
            if (_toolModeBeforeDoubleTapImageSelect != null) {
              _toolMode = _toolModeBeforeDoubleTapImageSelect!;
              _toolModeBeforeDoubleTapImageSelect = null;
            }
          }
        });
      } else if (_toolMode == CanvasToolMode.lasso ||
          _isSecondaryBarrelPressed) {
        // Holding the secondary stylus barrel button and dragging gives a
        // temporary Lasso Select, regardless of whichever tool is actually
        // active -- same override pattern the primary barrel button
        // already uses for the Eraser.
        setState(() {
          _lassoPoints = [worldPos];
          _selectedLines.clear();
        });
      } else if ((_toolMode == CanvasToolMode.eraser ||
              _isStylusBarrelPressed) &&
          _eraserMode == EraserMode.stroke) {
        // Stroke Eraser Mode: Tapping on a stroke line immediately erases
        // the whole line! `includeImages: false` -- the Eraser tool must
        // never be able to touch an image, whichever kind (see
        // `_findLineAt`'s doc comment).
        final hitLine = _findLineAt(worldPos, includeImages: false);
        if (hitLine != null) {
          setState(() {
            final group = hitLine.groupId != null
                ? _lines.where((l) => l.groupId == hitLine.groupId).toSet()
                : {hitLine};
            _recordAction(MathsPadAction(removedLines: group.toList()));
            _lines.removeWhere((l) => group.contains(l));
            _selectedLines.removeAll(group);
            _removeOrphanedAngleLabels(group);
          });
        }
      } else {
        final bool isEraserStroke =
            _toolMode == CanvasToolMode.eraser || _isStylusBarrelPressed;
        // Pressure-sensitive width, ink only (not the eraser) -- fixed for
        // the whole stroke from how hard the pen first touched down,
        // rather than continuously tapering, so an already-drawn part of
        // the line never visibly changes width later in the same stroke.
        // At the default pressure of 1.0 (every non-stylus device: mouse,
        // plain touch) this multiplier is exactly 1.0, so nothing changes
        // for anyone without a pressure-sensitive pen.
        final double pressureMultiplier = (0.5 + _currentPointerPressure * 0.5)
            .clamp(0.4, 1.6);
        // Pencil is a completely separate tool from Pen -- it never uses
        // Pen's fixed-per-stroke `pressureMultiplier` (perfect_freehand
        // does its own continuous pressure tapering instead) and never
        // triggers Magic Pen mode.
        final bool isPencilStroke =
            !isEraserStroke && _toolMode == CanvasToolMode.pencil;
        final double activeWidth = isEraserStroke
            ? _eraserWidth
            : (isPencilStroke ? _pencilWidth : _penWidth * pressureMultiplier);

        final newLine = MathsPadLine(
          points: [MathsPadStrokePoint(worldPos, _lastPencilStylusPressure)],
          color: _selectedColor,
          strokeWidth: activeWidth,
          isEraser: isEraserStroke,
          isPencil: isPencilStroke,
          isMagic:
              !isEraserStroke &&
              _toolMode == CanvasToolMode.pen &&
              _isMagicPenMode,
        );
        _currentLine = newLine;
        _predictedTailPresent = false;
        _resetPenAutoShape();

        _selectedLines.clear();
        _activeDrawingNotifier.value++;
      }
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    // Trackpad-driven pinch/pan is handled entirely by `onPointerPanZoomUpdate`
    // below (which has access to reliable raw pan/scale/cursor data) --
    // `ScaleGestureRecognizer` ALSO auto-synthesizes `onScaleUpdate` calls
    // from the same underlying `PointerPanZoomUpdateEvent` stream, but its
    // synthesized `details.localFocalPoint` drifts far from the true cursor
    // position as the gesture progresses (confirmed via diagnostic capture:
    // cursor stayed fixed on screen while the synthesized focal point
    // drifted from ~(640,280) to ~(-19,-59) over one pinch) -- a Flutter-
    // level quirk with trackpad-sourced scale gestures, not something a
    // different formula here can fix. Skip entirely so the two handlers
    // don't fight over `_panOffset`/`_scale`.
    if (_isPanZoomGestureActive) return;
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
      if (!_zoomLocked) {
        _scale = (_initialScale * details.scale).clamp(0.25, 4.0);
        _scaleNotifier.value = _scale;
      }
      // Anchor to the WORLD point that was under the focal point at gesture
      // start, so it stays under the (possibly moving) focal point at every
      // new scale -- the old formula (`_initialPanOffset + focalDelta`) only
      // accounted for the focal point's own screen-space movement, not the
      // scale change, so a pinch centered on one spot would zoom around the
      // canvas's pan origin instead of around the pinch center. This
      // reduces to the exact old panning formula when `_zoomLocked` (scale
      // stays `_initialScale`), so locked-zoom panning is unaffected.
      final Offset worldFocal =
          (_initialFocalPoint - _initialPanOffset) / _initialScale;
      _panOffset = _clampPanIfLocked(
        details.localFocalPoint - worldFocal * _scale,
      );
      _panNotifier.value = _panOffset;
      return;
    } else if (_draggedInstrument != null) {
      _updateInstrumentDrag(_screenToWorld(details.localFocalPoint));
      return;
    } else if (_resizingTextLabelIndex != null) {
      _updateTextResizeHandle(_screenToWorld(details.localFocalPoint));
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
        // No `_finishedStrokesNotifier`/`_resetBaking()` here -- a
        // selected line is skipped entirely by the Layer 1a/1b finished-
        // strokes painters (see `_MathsPadFinishedStrokesPainter`'s
        // `selectedLines` doc comment) and instead drawn live, every
        // frame, by Layer 2 below, on top of everything else. That used
        // to mean nuking EVERY baked chunk on the page on every single
        // drag-update frame just to move one line -- catastrophically
        // expensive on a heavy page, and the actual cause of the
        // selection outline/drag feeling laggy, not the outline's own
        // glow animation.
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
          // A Fill Tool region (or pasted image) is a raster image, not a
          // real stroke -- rotating its two bounding corner points would
          // only skew the (still axis-aligned) rect, not actually rotate
          // the image. Instead spin it in place around its own bounding-box
          // center by accumulating an angle applied at paint time, leaving
          // its points/bounds (used for hit-testing/selection) untouched --
          // matching how a freehand stroke rotates around its own center.
          if (line.fillImage != null) {
            line.rotation += angleDelta;
            continue;
          }

          // Rotate all points around the shared group center (_transformCenter)
          // so every stroke in the selection moves as one rigid entity.
          for (int i = 0; i < line.points.length; i++) {
            final loc = line.points[i].offset - _transformCenter!;
            final rotX = loc.dx * cosA - loc.dy * sinA;
            final rotY = loc.dx * sinA + loc.dy * cosA;
            line.points[i].offset = _transformCenter! + Offset(rotX, rotY);
          }
          line.invalidateCache();
        }
        // See the Move branch above for why no `_finishedStrokesNotifier`/
        // `_resetBaking()` here.
        _activeDrawingNotifier.value++;
      } else {
        // Corner Resize (Scale) Mode
        final selectionBounds = _getSelectionBounds();
        if (selectionBounds != null) {
          final Offset anchor = _getResizeAnchor(
            _activeHandle,
            selectionBounds,
          );
          final Offset localWorldPos = _rotatePointAround(
            worldPos,
            selectionBounds.center,
            -_selectedImageRotation,
          );
          final double currentDist = (localWorldPos - anchor).distance;
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
          // See the Move branch above for why no `_finishedStrokesNotifier`/
          // `_resetBaking()` here.
          _activeDrawingNotifier.value++;
        }
      }
      return;
    } else if ((_toolMode == CanvasToolMode.eraser || _isStylusBarrelPressed) &&
        _eraserMode == EraserMode.stroke) {
      // Stroke Eraser Mode: Dragging across stroke lines erases each whole
      // line touched. `includeImages: false` -- same as the tap variant
      // above, the Eraser tool must never touch an image.
      final worldPos = _screenToWorld(details.localFocalPoint);
      final hitLine = _findLineAt(worldPos, includeImages: false);
      if (hitLine != null) {
        final group = hitLine.groupId != null
            ? _lines.where((l) => l.groupId == hitLine.groupId).toSet()
            : {hitLine};
        _recordAction(MathsPadAction(removedLines: group.toList()));
        _lines.removeWhere((l) => group.contains(l));
        _selectedLines.removeAll(group);
        _removeOrphanedAngleLabels(group);
        _finishedStrokesNotifier.value++;
        _resetBaking();
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
      // See the handle-based Move branch above for why no
      // `_finishedStrokesNotifier`/`_resetBaking()` here.
      _activeDrawingNotifier.value++;
    } else if (_toolMode == CanvasToolMode.laser) {
      _addLaserPoint(_screenToWorld(details.localFocalPoint));
    } else if ((_toolMode == CanvasToolMode.lasso || _isSecondaryBarrelPressed) &&
        _lassoPoints.isNotEmpty) {
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
    } else if (_toolMode == CanvasToolMode.polygonAngle &&
        _currentLine != null) {
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
    } else if (_toolMode == CanvasToolMode.square && _currentLine != null) {
      // setState needed (same reason as the circle/arc tool above): the
      // live length badge lives in the instruments-overlay Stack.
      setState(() {
        _handleSquareToolUpdate(_screenToWorld(details.localFocalPoint));
      });
    } else if (_currentLine != null) {
      // 1-finger freehand drawing stroke update
      final worldPos = _screenToWorld(details.localFocalPoint);

      // Any speculative predicted tail point (see `_onStylusPredictedDelta`)
      // must never influence auto-shape snapping or get compounded with a
      // real point -- always strip it first, before anything else below.
      if (_predictedTailPresent && _currentLine!.points.isNotEmpty) {
        _currentLine!.points.removeLast();
        _predictedTailPresent = false;
      }

      if (_penAutoCircled && _penAutoCircleCenter != null) {
        // Already snapped to a circle by the hold -- keep resizing its
        // radius to follow the pointer's distance from the center,
        // instead of resuming freehand point sampling.
        final double newRadius = (worldPos - _penAutoCircleCenter!).distance;
        _currentLine!.points
          ..clear()
          ..addAll(_circleOutlinePoints(_penAutoCircleCenter!, newRadius));
        _currentLine!.invalidateCache();
        _activeDrawingNotifier.value++;
        return;
      }

      if (_penAutoStraightened) {
        // Already snapped to a straight line by the hold -- keep its
        // endpoint following the pointer, same as the Straight Line Tool,
        // instead of resuming freehand point sampling.
        final Offset start = _currentLine!.points.first.offset;
        _currentLine!.points
          ..clear()
          ..add(MathsPadStrokePoint(start))
          ..add(MathsPadStrokePoint(worldPos));
        _activeDrawingNotifier.value++;
        return;
      }

      final double minDist = _currentLine!.isPencil ? 2.0 : 1.2;
      if (_currentLine!.points.isEmpty ||
          (worldPos - _currentLine!.points.last.offset).distance >= minDist) {
        _currentLine!.points.add(
          MathsPadStrokePoint(worldPos, _lastPencilStylusPressure),
        );
        if (_currentLine!.isEraser) {
          // NOT `_finishedStrokesNotifier.value++` here -- the eraser
          // stroke only gets merged into `_lines` at gesture-end (see
          // `_onScaleEnd`), so during the drag `_lines` never actually
          // changes; repainting the ENTIRE finished-strokes layer (every
          // line on the page, behind a `saveLayer`) on every single move
          // sample was producing pixel-identical output every time --
          // pure wasted O(total ink) work every frame, and the dominant
          // cause of "lag that gets worse the more you've drawn". The
          // eraser's actual clearing effect still applies correctly in
          // one shot when the stroke commits below. `_eraserCursorPos`
          // instead drives a cheap live cursor ring on the (already
          // per-frame-repainting) active overlay layer, so dragging the
          // eraser still shows real-time feedback -- previously it
          // showed none at all, since `BlendMode.clear` on the active
          // layer's own separate compositing surface has no visible
          // effect on the finished layer underneath it.
          _eraserCursorPos = worldPos;
        }
        // Fold the stroke-so-far into Layer 2a's cached snapshot once
        // enough new points have accumulated -- see `_kLiveBakeEvery`'s
        // doc comment (fixes "writing a long line/sentence gets
        // progressively slower the longer it runs"). Pencil strokes are
        // deliberately never baked here -- their perfect_freehand outline
        // is recomputed fresh every frame by the Active Overlay layer
        // instead (see `_MathsPadActiveOverlayPainter.paint`), so
        // `liveBakedPointCount` staying 0 for the whole stroke is what
        // keeps Layer 2a a no-op for them.
        if (!_currentLine!.isPencil &&
            _currentLine!.points.length - _currentLine!.liveBakedPointCount >=
                _kLiveBakeEvery) {
          _currentLine!.liveBakedPointCount = _currentLine!.points.length;
        }
        _activeDrawingNotifier.value++;
      }

      // Hold-to-straighten: Pen ink only -- never the Pencil tool, which
      // stays pure freehand with no auto-shape snapping.
      if (!_currentLine!.isEraser && !_currentLine!.isPencil) {
        const double holdTolerance = 6.0;
        if (_penHoldAnchor == null ||
            (worldPos - _penHoldAnchor!).distance > holdTolerance) {
          _penHoldAnchor = worldPos;
          _penHoldTimer?.cancel();
          final MathsPadLine lineAtArm = _currentLine!;
          final Offset anchorForThisHold = worldPos;
          _penHoldTimer = Timer(const Duration(seconds: 1), () {
            if (!mounted || _currentLine != lineAtArm) return;
            _tryAutoShapePenLine(anchorForThisHold);
          });
        }
      }
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_toolMode == CanvasToolMode.laser) {
      // The trail keeps fading on its own via `_laserFadeTimer` -- nothing
      // to commit or clean up on release.
      return;
    }
    if (_draggedInstrument != null) {
      _endInstrumentDrag();
      return;
    }
    if (_resizingTextLabelIndex != null) {
      _endTextResizeHandle();
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
    if (_toolMode == CanvasToolMode.square) {
      setState(() {
        _handleSquareToolEnd();
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
          _recordAction(MathsPadAction(addedLines: newShapeLines));
          _toolMode = CanvasToolMode.pen;
          _selectedWidth = _penWidth;
          _activeShapeTool = null;
        });
        _finishedStrokesNotifier.value++;
        _maybeRebakeLines();
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

    // Perform Lasso Selection: enclosed strokes become selected for Move or
    // Duplicate -- also fires for a secondary-barrel-held drag, matching
    // its temporary Lasso override in `_onScaleStart`/`_onScaleUpdate`.
    if ((_toolMode == CanvasToolMode.lasso || _isSecondaryBarrelPressed) &&
        _lassoPoints.length > 2) {
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
            final group = line.groupId != null
                ? _lines.where((l) => l.groupId == line.groupId).toSet()
                : {line};
            selectedContained.addAll(group);
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
      final bool wasEraser = _currentLine!.isEraser;

      if (wasEraser && _eraserMode == EraserMode.area) {
        final eraserLine = _currentLine!;
        final double eraserRadius = (eraserLine.strokeWidth * 3.5) / 2.0;
        final Rect eraserBounds = _computeLineBounds(
          eraserLine,
        ).inflate(eraserRadius);

        List<MathsPadLine> newLines = [];
        List<MathsPadLine> removedLines = [];
        List<MathsPadLine> addedFragments = [];
        bool anyCut = false;

        for (final line in _lines) {
          if (line.isEraser || line.fillImage != null) {
            newLines.add(line);
            continue;
          }
          final Rect lineBounds = line.cachedBounds ?? _computeLineBounds(line);
          if (!eraserBounds.overlaps(lineBounds)) {
            newLines.add(line);
            continue;
          }

          // Resample line points to handle long straight segments crossing the eraser
          List<MathsPadStrokePoint> resampledPoints = [];
          for (int i = 0; i < line.points.length - 1; i++) {
            final p1 = line.points[i].offset;
            final p2 = line.points[i + 1].offset;
            double dist = (p2 - p1).distance;
            int steps = (dist / 2.0).ceil().clamp(1, 9999);
            for (int step = 0; step < steps; step++) {
              resampledPoints.add(
                MathsPadStrokePoint(Offset.lerp(p1, p2, step / steps)!),
              );
            }
          }
          resampledPoints.add(line.points.last);

          List<List<MathsPadStrokePoint>> keptSegments = [[]];
          bool lineCut = false;

          for (final rp in resampledPoints) {
            bool isErased = false;
            if (eraserLine.points.length == 1) {
              if ((rp.offset - eraserLine.points.first.offset).distance <=
                  eraserRadius) {
                isErased = true;
              }
            } else {
              for (int j = 0; j < eraserLine.points.length - 1; j++) {
                if (_distToSegment(
                      rp.offset,
                      eraserLine.points[j].offset,
                      eraserLine.points[j + 1].offset,
                    ) <=
                    eraserRadius) {
                  isErased = true;
                  break;
                }
              }
            }

            if (isErased) {
              if (keptSegments.last.isNotEmpty) {
                keptSegments.add([]);
              }
              lineCut = true;
            } else {
              keptSegments.last.add(rp);
            }
          }

          if (!lineCut) {
            newLines.add(line);
          } else {
            anyCut = true;
            removedLines.add(line);
            for (final seg in keptSegments) {
              if (seg.length >= 2) {
                final newLine = MathsPadLine(
                  points: seg,
                  color: line.color,
                  strokeWidth: line.strokeWidth,
                  isMagic: line.isMagic,
                  isShape: line.isShape,
                  isPencil: line.isPencil,
                  groupId: line.groupId,
                  isPastedImage: line.isPastedImage,
                );
                _buildAndCachePath(newLine);
                newLines.add(newLine);
                addedFragments.add(newLine);
              }
            }
          }
        }

        if (anyCut) {
          _lines.clear();
          _lines.addAll(newLines);
          _recordAction(
            MathsPadAction(
              addedLines: addedFragments,
              removedLines: removedLines,
            ),
          );
          _resetBaking();
        }

        _currentLine = null;
        _eraserCursorPos = null;
        _resetPenAutoShape();
        _finishedStrokesNotifier.value++;
        _activeDrawingNotifier.value++;
      } else {
        // A speculative predicted tail point must never become part of the
        // permanently committed stroke -- see `_onStylusPredictedDelta`.
        if (_predictedTailPresent && _currentLine!.points.isNotEmpty) {
          _currentLine!.points.removeLast();
          _predictedTailPresent = false;
        }
        _currentLine!.invalidateCache();
        _buildAndCachePath(_currentLine!);
        _lines.add(_currentLine!);
        _recordAction(MathsPadAction(addedLines: [_currentLine!]));
        _currentLine = null;
        _eraserCursorPos = null;
        _resetPenAutoShape();
        _finishedStrokesNotifier.value++;
        _activeDrawingNotifier.value++;

        if (wasEraser) {
          _resetBaking();
        } else {
          _maybeRebakeLines();
        }
      }
    }
    _snappedEdgeStart = null;
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

  void _selectAllLines() {
    setState(() {
      _selectedLines.clear();
      _selectedLines.addAll(
        _lines.where((line) => !line.isEraser && line.points.isNotEmpty),
      );
    });
  }

  void _moveSelectedLines(Offset offset) {
    if (_selectedLines.isEmpty) return;
    setState(() {
      for (final line in _selectedLines) {
        if (line.fillWorldBounds != null) {
          line.fillWorldBounds = line.fillWorldBounds!.shift(offset);
          for (var pt in line.points) {
            pt.offset += offset;
          }
        } else {
          for (var pt in line.points) {
            pt.offset += offset;
          }
          if (line.cachedBounds != null) {
            line.cachedBounds = line.cachedBounds!.shift(offset);
          }
        }
        line.invalidateCache();
      }
    });
  }

  // Copy selected strokes into clipboard (Ctrl+C)
  void _copySelectedLines() {
    if (_selectedLines.isEmpty) return;
    setState(() {
      _clipboard = _selectedLines.map((line) {
        return MathsPadLine(
          points: line.points
              .map((p) => MathsPadStrokePoint(p.offset, p.pressure))
              .toList(),
          color: line.color,
          strokeWidth: line.strokeWidth,
          isEraser: line.isEraser,
          isShape: line.isShape,
          isPencil: line.isPencil,
          fillImage: line.fillImage,
          fillWorldBounds: line.fillWorldBounds,
          rotation: line.rotation,
          isPastedImage: line.isPastedImage,
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

    final Map<String, String> groupMapping = {};

    final List<MathsPadLine> pasted = _clipboard.map<MathsPadLine>((line) {
      String? newGroupId;
      if (line.groupId != null) {
        newGroupId = groupMapping.putIfAbsent(
          line.groupId!,
          () => '${DateTime.now().microsecondsSinceEpoch}_${line.groupId}',
        );
      }

      final newLine = MathsPadLine(
        points: line.points
            .map(
              (p) => MathsPadStrokePoint(p.offset + translation, p.pressure),
            )
            .toList(),
        color: line.color,
        strokeWidth: line.strokeWidth,
        isEraser: line.isEraser,
        isShape: line.isShape,
        isPencil: line.isPencil,
        fillImage: line.fillImage,
        fillWorldBounds: line.fillWorldBounds?.shift(translation),
        rotation: line.rotation,
        groupId: newGroupId,
        isPastedImage: line.isPastedImage,
      );
      _buildAndCachePath(newLine);
      return newLine;
    }).toList();

    setState(() {
      _lines.addAll(pasted);
      _selectedLines.clear();
      _selectedLines.addAll(pasted);
      _recordAction(MathsPadAction(addedLines: pasted));
    });
    _finishedStrokesNotifier.value++;
    _maybeRebakeLines();
  }

  /// Pastes from the OS clipboard (content copied from OUTSIDE the app --
  /// a screenshot, an image copied from a browser, or plain text) at
  /// [atWorldPos], preferring an image if one is present, then plain text.
  /// Falls back to the existing same-app duplicate-selection paste
  /// (`_pasteClipboard`) if the system clipboard has nothing usable or the
  /// clipboard API isn't available on this platform/build.
  Future<void> _pasteFromSystemClipboard({Offset? atWorldPos}) async {
    final Offset placementPos =
        atWorldPos ??
        _lastPointerWorldPos ??
        _screenToWorld(Offset(_canvasSize.width / 2, _canvasSize.height / 2));

    try {
      final SystemClipboard? clipboard = SystemClipboard.instance;
      if (clipboard == null) {
        _pasteClipboard();
        return;
      }
      final ClipboardReader reader = await clipboard.read();

      const List<SimpleFileFormat> imageFormats = [
        Formats.png,
        Formats.jpeg,
        Formats.gif,
        Formats.webp,
        Formats.tiff,
      ];
      for (final format in imageFormats) {
        if (reader.canProvide(format)) {
          final Uint8List? bytes = await _readClipboardFileBytes(
            reader,
            format,
          );
          if (bytes != null && bytes.isNotEmpty) {
            await _insertPastedImageBytes(bytes, placementPos);
            return;
          }
        }
      }

      // Some sources (e.g. Ctrl+C on an image file in Windows File
      // Explorer, or a file dragged from Finder) put a file reference on
      // the clipboard instead of raw image bytes. Read the file from disk
      // in that case. Not applicable on web (no filesystem access there).
      if (!kIsWeb && reader.canProvide(Formats.fileUri)) {
        final Uri? fileUri = await reader.readValue(Formats.fileUri);
        if (fileUri != null && fileUri.isScheme('file')) {
          const imageExtensions = {
            '.png',
            '.jpg',
            '.jpeg',
            '.gif',
            '.webp',
            '.bmp',
            '.tiff',
          };
          final String path = fileUri.toFilePath();
          final String ext = path.contains('.')
              ? path.substring(path.lastIndexOf('.')).toLowerCase()
              : '';
          if (imageExtensions.contains(ext)) {
            try {
              final Uint8List bytes = await File(path).readAsBytes();
              if (bytes.isNotEmpty) {
                await _insertPastedImageBytes(bytes, placementPos);
                return;
              }
            } catch (e) {
              debugPrint('Mathpad paste: failed to read image file $path: $e');
            }
          }
        }
      }

      if (reader.canProvide(Formats.plainText)) {
        final String? text = await reader.readValue(Formats.plainText);
        final String trimmed = text?.trim() ?? '';
        if (trimmed.isNotEmpty) {
          setState(() {
            final newLabel = MathsPadTextLabel(
              position: placementPos,
              text: trimmed,
              color: _selectedColor,
            );
            _textLabels.add(newLabel);
            _recordAction(MathsPadAction(addedLabels: [newLabel]));
          });
          return;
        }
      }
    } catch (e) {
      // Clipboard read API unsupported/unavailable on this platform or
      // build -- fall through to the same-app duplicate-paste below.
      debugPrint('Mathpad paste: system clipboard read failed: $e');
    }

    _pasteClipboard();
  }

  /// Reads the full bytes of a clipboard [FileFormat] entry (e.g. a pasted
  /// image). `super_clipboard`'s [ClipboardReader.readValue] only supports
  /// small in-memory [ValueFormat]s (text/URIs); file-backed formats like
  /// images are delivered through the callback-based [DataReader.getFile]
  /// instead, so this wraps that into a plain awaitable result.
  Future<Uint8List?> _readClipboardFileBytes(
    ClipboardReader reader,
    FileFormat format,
  ) {
    final completer = Completer<Uint8List?>();
    final progress = reader.getFile(
      format,
      (file) async {
        final bytes = await file.readAll();
        if (!completer.isCompleted) completer.complete(bytes);
      },
      onError: (e) {
        debugPrint('Mathpad paste: failed to read clipboard file: $e');
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    if (progress == null) return Future.value(null);
    return completer.future;
  }

  /// Decodes pasted image [bytes] and adds them as an image-backed
  /// `MathsPadLine` (the same mechanism the Fill Tool uses), centered at
  /// [placementPos] and scaled down (never up) to fit within a reasonable
  /// max on-canvas size so a large screenshot doesn't dominate the canvas.
  Future<void> _insertPastedImageBytes(
    Uint8List bytes,
    Offset placementPos,
  ) async {
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image image = frame.image;

    double w = image.width.toDouble();
    double h = image.height.toDouble();
    if (w <= 0 || h <= 0 || !mounted) {
      image.dispose();
      return;
    }
    const double maxDim = 400.0;
    final double scale = (w > h ? maxDim / w : maxDim / h).clamp(0.0, 1.0);
    w *= scale;
    h *= scale;

    final Rect bounds = Rect.fromCenter(
      center: placementPos,
      width: w,
      height: h,
    );
    final MathsPadLine pastedLine = MathsPadLine(
      points: [
        MathsPadStrokePoint(bounds.topLeft),
        MathsPadStrokePoint(bounds.bottomRight),
      ],
      color: _selectedColor,
      strokeWidth: 0,
      fillImage: image,
      fillWorldBounds: bounds,
      isPastedImage: true,
    );

    setState(() {
      _lines.add(pastedLine);
      _recordAction(MathsPadAction(addedLines: [pastedLine]));
    });
    _finishedStrokesNotifier.value++;
    _maybeRebakeLines();
    // Pasting doesn't always involve a fresh pointer-down on the canvas
    // itself (e.g. the long-press "Paste" popup button, or Ctrl+V with
    // nothing else clicked in between) -- without reclaiming focus here
    // too, an immediate Ctrl+Z right after pasting an image would silently
    // go nowhere. See `_onPointerDown`'s matching doc comment.
    _canvasFocusNode.requestFocus();
  }

  // Duplicate Selected Strokes
  void _duplicateSelectedLines() {
    if (_selectedLines.isEmpty) return;

    final List<MathsPadLine> duplicatedLines = [];
    const Offset copyOffset = Offset(25.0, 25.0);

    final Map<String, String> groupMapping = {};

    for (final line in _selectedLines) {
      String? newGroupId;
      if (line.groupId != null) {
        newGroupId = groupMapping.putIfAbsent(
          line.groupId!,
          () => '${DateTime.now().microsecondsSinceEpoch}_${line.groupId}',
        );
      }

      final newPoints = line.points
          .map<MathsPadStrokePoint>(
            (p) => MathsPadStrokePoint(p.offset + copyOffset, p.pressure),
          )
          .toList();
      final newLine = MathsPadLine(
        points: newPoints,
        color: line.color,
        strokeWidth: line.strokeWidth,
        isEraser: line.isEraser,
        isShape: line.isShape,
        isPencil: line.isPencil,
        fillImage: line.fillImage,
        fillWorldBounds: line.fillWorldBounds?.shift(copyOffset),
        rotation: line.rotation,
        groupId: newGroupId,
        isPastedImage: line.isPastedImage,
      );
      _buildAndCachePath(newLine);
      duplicatedLines.add(newLine);
    }

    setState(() {
      _lines.addAll(duplicatedLines);
      _recordAction(MathsPadAction(addedLines: duplicatedLines));
      _selectedLines.clear();
      _selectedLines.addAll(duplicatedLines);
    });
    _finishedStrokesNotifier.value++;
    _maybeRebakeLines();
  }

  /// Recolours every currently-selected stroke/shape in place (mutating
  /// `MathsPadLine.color` rather than swapping in new line objects, so
  /// `_selectedLines` membership and any fixed angle label's `sourceLines`
  /// reference stay valid). Fill Tool results are skipped -- their colour
  /// lives in already-rasterized pixels, not this field, so setting it
  /// wouldn't visibly do anything.
  void _recolorSelectedLines(Color newColor) {
    if (_selectedLines.isEmpty) return;
    setState(() {
      for (final line in _selectedLines) {
        if (line.fillImage != null) continue;
        line.color = newColor;
      }
    });
    _finishedStrokesNotifier.value++;
    _resetBaking();
  }

  void _deleteSelectedLines() {
    if (_selectedLines.isNotEmpty) {
      setState(() {
        _recordAction(MathsPadAction(removedLines: _selectedLines.toList()));
        _lines.removeWhere((line) => _selectedLines.contains(line));
        _removeOrphanedAngleLabels(_selectedLines);
        _selectedLines.clear();
      });
      _finishedStrokesNotifier.value++;
      _resetBaking();
    }
  }

  /// Moves every selected line to the very END of `_lines` -- since
  /// `_MathsPadFinishedStrokesPainter.paint`'s Pass 2 now draws ink and
  /// pasted images in true chronological order, that means drawing LAST,
  /// i.e. on top of everything else once deselected (a selected line
  /// already renders on top live regardless -- see
  /// `_drawSelectedLinesOnTop` -- so this only visibly matters after
  /// deselecting). Exposed for images specifically (see the Floating
  /// Action Bar's "Bring to Front"/"Send to Back" buttons, only shown
  /// when the selection includes a pasted image), but works for any
  /// line -- a Fill Tool result just won't visibly move, since Pass 1
  /// always draws it at the very bottom regardless of `_lines` order.
  void _bringSelectedToFront() {
    if (_selectedLines.isEmpty) return;
    setState(() {
      final List<MathsPadLine> moved = _lines
          .where(_selectedLines.contains)
          .toList();
      _lines.removeWhere(_selectedLines.contains);
      _lines.addAll(moved);
    });
    _finishedStrokesNotifier.value++;
    // A one-off full reorder, not a per-frame drag update -- unlike the
    // live move/rotate/resize case this doesn't need to avoid
    // `_resetBaking()` (see `_onScaleUpdate`'s doc comments there); every
    // baked chunk's assumed relative ordering is genuinely stale now and
    // needs rebuilding, and this only runs once per button tap.
    _resetBaking();
  }

  /// The mirror of `_bringSelectedToFront` -- moves every selected line
  /// to the very START of `_lines` instead, so it draws first/underneath
  /// everything else once deselected.
  void _sendSelectedToBack() {
    if (_selectedLines.isEmpty) return;
    setState(() {
      final List<MathsPadLine> moved = _lines
          .where(_selectedLines.contains)
          .toList();
      _lines.removeWhere(_selectedLines.contains);
      _lines.insertAll(0, moved);
    });
    _finishedStrokesNotifier.value++;
    _resetBaking();
  }

  /// Whether the single selected image is currently "stuck" to any other
  /// lines -- i.e. has a `groupId` at all. Drives the Floating Action
  /// Bar's pin icon's on/off appearance; see `_toggleStickDrawingsToImage`.
  bool get _selectedImageIsStuck =>
      _selectedLines.length == 1 && _selectedLines.first.groupId != null;

  /// Toggle for the Floating Action Bar's "stick" pin, shown only when
  /// exactly one pasted image is selected. Reuses the same `groupId`
  /// mechanism a Shape Tool result's pieces already share (so tap-select/
  /// the Eraser tool/dragging a group already treat every member as one
  /// unit, with no new plumbing needed elsewhere):
  ///  - Not yet stuck (`groupId == null`): assigns a fresh `groupId` to
  ///    the image AND to every OTHER line currently overlapping its
  ///    bounds, so from now on they all move/rotate/resize together --
  ///    "sticking" whatever ink is currently drawn on the image to it.
  ///  - Already stuck: clears `groupId` from every line that shares it
  ///    (the image included), releasing them all back to independent
  ///    strokes.
  /// Only lines overlapping the image AT THE MOMENT this is pressed get
  /// stuck -- it's a one-shot grouping action, not an ongoing "everything
  /// drawn on this image from now on auto-sticks" mode; press it again
  /// after adding more ink on top to pull that in too.
  void _toggleStickDrawingsToImage() {
    if (_selectedLines.length != 1) return;
    final MathsPadLine image = _selectedLines.first;
    if (image.fillImage == null || image.fillWorldBounds == null) return;

    setState(() {
      if (image.groupId != null) {
        final String gid = image.groupId!;
        for (final line in _lines) {
          if (line.groupId == gid) line.groupId = null;
        }
      } else {
        final String gid =
            '${DateTime.now().microsecondsSinceEpoch}_stick_${identityHashCode(image)}';
        image.groupId = gid;
        final Rect imageBounds = image.fillWorldBounds!;
        for (final line in _lines) {
          if (identical(line, image) || line.points.isEmpty) continue;
          double minX = line.points.first.offset.dx;
          double maxX = minX;
          double minY = line.points.first.offset.dy;
          double maxY = minY;
          for (final p in line.points) {
            if (p.offset.dx < minX) minX = p.offset.dx;
            if (p.offset.dx > maxX) maxX = p.offset.dx;
            if (p.offset.dy < minY) minY = p.offset.dy;
            if (p.offset.dy > maxY) maxY = p.offset.dy;
          }
          final Rect bounds = Rect.fromLTRB(minX, minY, maxX, maxY);
          if (bounds.overlaps(imageBounds)) {
            line.groupId = gid;
          }
        }
        // Reflect the newly-stuck members in the live selection too, so
        // the neon outline/selection box immediately shows the whole
        // group as selected -- matching what tapping any one member
        // would already do via the existing groupId-based
        // selection-expansion (see the `tapSelect` branch).
        _selectedLines
          ..clear()
          ..addAll(_lines.where((l) => l.groupId == gid));
      }
    });
    _finishedStrokesNotifier.value++;
    _resetBaking();
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
            MathsPadStrokePoint(
              center + Offset(cos(a) * radiusX, sin(a) * radiusY),
            ),
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
            MathsPadStrokePoint(
              center + Offset(cos(a) * radiusX, sin(a) * radiusY),
            ),
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
            MathsPadStrokePoint(
              center + Offset(cos(a) * radiusX, sin(a) * radiusY),
            ),
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

      case BasicShapeType.cone3d:
        final List<MathsPadStrokePoint> basePts = [];
        final double baseCenterY = rect.bottom - rect.height * 0.15;
        final double ellipseRY = rect.height * 0.15;
        for (int i = 0; i <= 36; i++) {
          final double a = (i / 36) * 2 * pi;
          basePts.add(
            MathsPadStrokePoint(
              Offset(
                center.dx + cos(a) * radiusX,
                baseCenterY + sin(a) * ellipseRY,
              ),
            ),
          );
        }
        createdLines.add(
          MathsPadLine(
            points: basePts,
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        createdLines.add(
          MathsPadLine(
            points: [
              MathsPadStrokePoint(Offset(rect.left, baseCenterY)),
              MathsPadStrokePoint(Offset(center.dx, rect.top)),
              MathsPadStrokePoint(Offset(rect.right, baseCenterY)),
            ],
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        break;

      case BasicShapeType.sphere3d:
        final List<MathsPadStrokePoint> circlePts = [];
        for (int i = 0; i <= 36; i++) {
          final double a = (i / 36) * 2 * pi;
          circlePts.add(
            MathsPadStrokePoint(
              center + Offset(cos(a) * radiusX, sin(a) * radiusY),
            ),
          );
        }
        createdLines.add(
          MathsPadLine(
            points: circlePts,
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        final List<MathsPadStrokePoint> equatorPts = [];
        final double equatorRY = radiusY * 0.3;
        for (int i = 0; i <= 36; i++) {
          final double a = (i / 36) * 2 * pi;
          equatorPts.add(
            MathsPadStrokePoint(
              center + Offset(cos(a) * radiusX, sin(a) * equatorRY),
            ),
          );
        }
        createdLines.add(
          MathsPadLine(
            points: equatorPts,
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        final List<MathsPadStrokePoint> verticalPts = [];
        final double equatorRX = radiusX * 0.3;
        for (int i = 0; i <= 36; i++) {
          final double a = (i / 36) * 2 * pi;
          verticalPts.add(
            MathsPadStrokePoint(
              center + Offset(cos(a) * equatorRX, sin(a) * radiusY),
            ),
          );
        }
        createdLines.add(
          MathsPadLine(
            points: verticalPts,
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        break;
    }

    final String shapeGroupId = DateTime.now().microsecondsSinceEpoch
        .toString();
    for (final line in createdLines) {
      line.groupId = shapeGroupId;
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

  // Direct notifier updates -- no `setState`, matching the pinch-to-zoom/
  // trackpad-pan gesture handlers. A `setState` here would rebuild
  // `_MathsPadWidgetState.build()`'s ENTIRE widget tree (toolbar, every
  // instrument, every text label, ...) on every single zoom button tap --
  // real, avoidable cost that was the direct cause of "zoom in/zoom out
  // feels laggy" (`_scale`/`_panOffset` are only ever read inside event
  // handlers, never during `build()`'s widget construction itself, so
  // nothing actually needs that full rebuild to stay correct).
  void _resetView() {
    _frictionController?.stop();
    _panOffset = _clampPanIfLocked(Offset.zero);
    _scale = 1.0;
    _panNotifier.value = _panOffset;
    _scaleNotifier.value = 1.0;
  }

  void _zoomIn() {
    if (_zoomLocked) return;
    _frictionController?.stop();
    _scale = (_scale * 1.2).clamp(0.25, 4.0);
    _scaleNotifier.value = _scale;
  }

  void _zoomOut() {
    if (_zoomLocked) return;
    _frictionController?.stop();
    _scale = (_scale / 1.2).clamp(0.25, 4.0);
    _scaleNotifier.value = _scale;
  }

  void _compressCanvasSpace() {
    if (_lines.isEmpty && _textLabels.isEmpty) return;

    List<_CanvasCluster> clusters = [];
    final Map<String, _CanvasCluster> groupClusters = {};

    for (final line in _lines) {
      Rect? lineBounds;
      if (line.fillWorldBounds != null) {
        lineBounds = line.fillWorldBounds;
      } else if (line.points.isNotEmpty) {
        double minX = double.infinity, minY = double.infinity;
        double maxX = -double.infinity, maxY = -double.infinity;
        for (final p in line.points) {
          if (p.offset.dx < minX) minX = p.offset.dx;
          if (p.offset.dx > maxX) maxX = p.offset.dx;
          if (p.offset.dy < minY) minY = p.offset.dy;
          if (p.offset.dy > maxY) maxY = p.offset.dy;
        }
        lineBounds = Rect.fromLTRB(minX, minY, maxX, maxY);
      }
      if (lineBounds == null) continue;

      if (line.groupId != null) {
        if (groupClusters.containsKey(line.groupId)) {
          final cluster = groupClusters[line.groupId!]!;
          cluster.lines.add(line);
          cluster.bounds = cluster.bounds.expandToInclude(lineBounds);
        } else {
          final cluster = _CanvasCluster(lineBounds);
          cluster.lines.add(line);
          groupClusters[line.groupId!] = cluster;
        }
      } else {
        final cluster = _CanvasCluster(lineBounds);
        cluster.lines.add(line);
        clusters.add(cluster);
      }
    }
    clusters.addAll(groupClusters.values);

    for (final label in _textLabels) {
      final cluster = _CanvasCluster(label.worldBounds);
      cluster.labels.add(label);
      clusters.add(cluster);
    }

    // Merge intersecting clusters
    bool merged;
    do {
      merged = false;
      for (int i = 0; i < clusters.length; i++) {
        for (int j = i + 1; j < clusters.length; j++) {
          if (clusters[i].bounds
              .inflate(5.0)
              .overlaps(clusters[j].bounds.inflate(5.0))) {
            clusters[i].merge(clusters[j]);
            clusters.removeAt(j);
            merged = true;
            break;
          }
        }
        if (merged) break;
      }
    } while (merged);

    const double minGap = 20.0;

    // Vertical Compaction (shift UP)
    clusters.sort((a, b) => a.bounds.top.compareTo(b.bounds.top));
    for (int i = 0; i < clusters.length; i++) {
      final cluster = clusters[i];
      double maxAllowedY = -double.infinity;
      for (int j = 0; j < i; j++) {
        final other = clusters[j];
        if (cluster.bounds.left <= other.bounds.right &&
            cluster.bounds.right >= other.bounds.left) {
          if (other.bounds.bottom > maxAllowedY) {
            maxAllowedY = other.bounds.bottom;
          }
        }
      }

      double shiftY = 0;
      if (maxAllowedY != -double.infinity) {
        final double targetY = maxAllowedY + minGap;
        if (cluster.bounds.top > targetY) {
          shiftY = targetY - cluster.bounds.top;
        }
      }
      if (shiftY < 0) {
        cluster.shift(Offset(0, shiftY));
      }
    }

    // Horizontal Compaction (shift LEFT)
    clusters.sort((a, b) => a.bounds.left.compareTo(b.bounds.left));
    for (int i = 0; i < clusters.length; i++) {
      final cluster = clusters[i];
      double maxAllowedX = -double.infinity;
      for (int j = 0; j < i; j++) {
        final other = clusters[j];
        if (cluster.bounds.top <= other.bounds.bottom &&
            cluster.bounds.bottom >= other.bounds.top) {
          if (other.bounds.right > maxAllowedX) {
            maxAllowedX = other.bounds.right;
          }
        }
      }

      double shiftX = 0;
      if (maxAllowedX != -double.infinity) {
        final double targetX = maxAllowedX + minGap;
        if (cluster.bounds.left > targetX) {
          shiftX = targetX - cluster.bounds.left;
        }
      }
      if (shiftX < 0) {
        cluster.shift(Offset(shiftX, 0));
      }
    }

    // Apply shifts to fixed angle labels
    for (final angleLabel in _fixedAngleLabels) {
      if (angleLabel.sourceLines.isNotEmpty) {
        for (final cluster in clusters) {
          if (cluster.lines.contains(angleLabel.sourceLines.first)) {
            angleLabel.vertex += cluster.totalShift;
            break;
          }
        }
      }
    }

    setState(() {
      _finishedStrokesNotifier.value++;
      _resetBaking();
      _activeDrawingNotifier.value++;
    });
  }

  void _undo() {
    if (_undoHistory.isNotEmpty) {
      setState(() {
        final action = _undoHistory.removeLast();
        action.undo(this);
        _redoHistory.add(action);
      });
    }
  }

  void _redo() {
    if (_redoHistory.isNotEmpty) {
      setState(() {
        final action = _redoHistory.removeLast();
        action.redo(this);
        _undoHistory.add(action);
      });
    }
  }

  void _recordAction(MathsPadAction action) {
    _undoHistory.add(action);
    _redoHistory.clear();
  }

  Future<void> _exportToPdf() async {
    final pdf = PdfDocument();

    // Calculate bounding box of all strokes
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final line in _lines) {
      if (line.points.isEmpty) continue;
      for (final p in line.points) {
        if (p.offset.dx < minX) minX = p.offset.dx;
        if (p.offset.dx > maxX) maxX = p.offset.dx;
        if (p.offset.dy < minY) minY = p.offset.dy;
        if (p.offset.dy > maxY) maxY = p.offset.dy;
      }
    }

    if (minX == double.infinity) minX = 0;
    if (minY == double.infinity) minY = 0;
    if (maxX == double.negativeInfinity) maxX = 800;
    if (maxY == double.negativeInfinity) maxY = 600;

    // Add padding
    minX -= 50;
    minY -= 50;
    maxX += 50;
    maxY += 50;

    double width = maxX - minX;
    double height = maxY - minY;

    pdf.pageSettings.size = Size(width, height);
    final page = pdf.pages.add();
    final graphics = page.graphics;

    graphics.translateTransform(-minX, -minY);

    for (final line in _lines) {
      if (line.points.isEmpty || line.isEraser) continue;

      final pdfPen = PdfPen(
        PdfColor(line.color.red, line.color.green, line.color.blue),
        width: line.strokeWidth,
      );

      if (line.points.length == 1) {
        graphics.drawEllipse(
          Rect.fromCircle(
            center: line.points[0].offset,
            radius: line.strokeWidth / 2,
          ),
          pen: pdfPen,
          brush: PdfSolidBrush(
            PdfColor(line.color.red, line.color.green, line.color.blue),
          ),
        );
      } else {
        final path = PdfPath();
        path.addLine(
          Offset(line.points[0].offset.dx, line.points[0].offset.dy),
          Offset(line.points[1].offset.dx, line.points[1].offset.dy),
        );
        for (int i = 1; i < line.points.length - 1; i++) {
          path.addLine(
            Offset(line.points[i].offset.dx, line.points[i].offset.dy),
            Offset(line.points[i + 1].offset.dx, line.points[i + 1].offset.dy),
          );
        }
        graphics.drawPath(path, pen: pdfPen);
      }
    }

    final bytes = await pdf.save();
    pdf.dispose();

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/mathpad_export.pdf');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles([XFile(file.path)], text: 'MathPad Export');
  }

  void _clearCanvas() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Canvas?'),
        content: const Text(
          'Are you sure you want to clear the entire canvas? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(context);
              _executeClearCanvas();
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _executeClearCanvas() {
    setState(() {
      _lines.clear();
      _undoHistory.clear();
      _redoHistory.clear();
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
    _resetBaking();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark =
        _themeMode == MathPadTheme.cosmos ||
        _themeMode == MathPadTheme.dark ||
        _themeMode == MathPadTheme.aswadLail;

    final bgColor = widget.isTransparentBg
        ? Colors.transparent
        : (_themeMode == MathPadTheme.cosmos
              ? const Color(0xFF0F2B52)
              : (_themeMode == MathPadTheme.aswadLail
                    ? const Color(0xFF000000)
                    : (isDark
                          ? const Color(0xFF0F172A)
                          : const Color(0xFFFCFDFE))));

    return PopScope(
      canPop: _recordingState != MathPadRecordingState.recording,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.pop(context, result);
        }
      },
      child: Focus(
        focusNode: _canvasFocusNode,
        autofocus: true,
        onKeyEvent: (node, event) {
          // `IgnorePointer` around the canvas/toolbar below only blocks
          // pointer input -- keyboard shortcuts reach this `Focus` node
          // regardless, so they need their own explicit guard to stay
          // inert while a heavy page's content is still hydrating (see
          // `_isHydratingInitialContent`).
          if (_isHydratingInitialContent) return KeyEventResult.ignored;
          if (event is KeyDownEvent) {
            final hw = HardwareKeyboard.instance;
            final ctrl = hw.isControlPressed;
            final shift = hw.isShiftPressed;

            if (ctrl && event.logicalKey == LogicalKeyboardKey.keyZ) {
              _undo();
              return KeyEventResult.handled;
            }
            if (ctrl && event.logicalKey == LogicalKeyboardKey.keyD) {
              _duplicateSelectedLines();
              return KeyEventResult.handled;
            }
            if (ctrl && event.logicalKey == LogicalKeyboardKey.keyA) {
              _selectAllLines();
              return KeyEventResult.handled;
            }
            if (ctrl && event.logicalKey == LogicalKeyboardKey.keyC) {
              _copySelectedLines();
              return KeyEventResult.handled;
            }
            if (ctrl && event.logicalKey == LogicalKeyboardKey.keyV) {
              _pasteFromSystemClipboard();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              if (shift) {
                widget.onToggleFullScreen?.call();
              } else if (widget.isFullScreen) {
                widget.onToggleFullScreen?.call();
              }
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.delete) {
              _deleteSelectedLines();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              _moveSelectedLines(const Offset(0, -10));
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              _moveSelectedLines(const Offset(0, 10));
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              _moveSelectedLines(const Offset(-10, 0));
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              _moveSelectedLines(const Offset(10, 0));
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
          child: Stack(
            children: [
              // Pointer input only (see the keyboard guard in `onKeyEvent`
              // above for the other half) -- inert while a heavy page's
              // `initialLines` are still being frame-batched into
              // `_bakedChunks` (`_hydrateNextInitialBatch`), since drawing/
              // undo/paste/tool-switching mid-hydration would race
              // `_bakedLineCount`'s bookkeeping, which assumes hydration
              // owns the front of `_lines` until it finishes.
              IgnorePointer(
                ignoring: _isHydratingInitialContent,
                child: _buildToolbarAndCanvas(context, isDark, bgColor),
              ),
              if (_isHydratingInitialContent) _buildHydrationOverlay(isDark),
              // Lives in THIS outer `Stack`, not inside the toolbar/canvas
              // subtree that `_isFullScreenMode` swaps layouts within -- so
              // it keeps showing at the very top edge (the bottom of the
              // docked top bar in the normal layout) even when Full Screen
              // hides the rest of the toolbar chrome.
              if (_recordingState == MathPadRecordingState.encoding)
                _buildEncodingProgressBar(),
            ],
          ),
        ),
      ),
    );
  }

  /// A thin neon progress bar reflecting real encode progress (from
  /// `MathPadRecordingService.onEncodingProgress`, parsed off ffmpeg's own
  /// `-progress` output -- see that service) instead of the old
  /// indeterminate spinner, so a lecture-length encode reads as "working,
  /// N% done" rather than "stuck". Same neon palette as
  /// `_NeonBorderPainter`'s live-recording border, so the two read as one
  /// continuous "something is actively happening" visual language across
  /// record -> encode.
  Widget _buildEncodingProgressBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      // Listens to `_recordingService` directly instead of going through
      // this page's own `setState` -- `encodingProgress` updates several
      // times a second while encoding, and this way that only ever
      // rebuilds this thin bar, not the whole page.
      child: ListenableBuilder(
        listenable: _recordingService,
        builder: (context, _) => IgnorePointer(
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(18),
            ),
            child: SizedBox(
              height: 4,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double fraction = _recordingService.encodingProgress
                      .clamp(0.0, 1.0);
                  return Stack(
                    children: [
                      Container(color: Colors.black.withValues(alpha: 0.35)),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        width: constraints.maxWidth * fraction,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF00F5FF), // cyan
                              Color(0xFF6366F1), // brand indigo
                              Color(0xFFFF00E5), // magenta
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF6366F1,
                              ).withValues(alpha: 0.9),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Shown only while `_isHydratingInitialContent` is true -- unlike the
  /// freeze this replaced, the UI thread is never blocked for more than
  /// one `_kBakeThreshold`-sized batch at a time now, so this genuinely
  /// animates instead of appearing to hang. Deliberately subtle/
  /// non-opaque: `_hydrateNextInitialBatch` seals one new baked chunk per
  /// frame, so the page's strokes are visibly painting themselves in
  /// underneath this the whole time, which reads as real progress rather
  /// than a blank wait.
  Widget _buildHydrationOverlay(bool isDark) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.12),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? _darkPanelColor : const Color(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Loading page…',
                    style: TextStyle(
                      color: isDark ? Colors.white : _darkPanelColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolbarAndCanvas(
    BuildContext context,
    bool isDark,
    Color bgColor,
  ) {
    // Infinite Writing Canvas Body -- shared between both toolbar layouts
    // below, since only where it sits (not how it's built) changes with
    // `_toolbarOnLeft`.
    final Widget canvasArea = Expanded(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Track the canvas's own size (excluding the toolbar beside/
          // above it) so newly-added instruments can be centered in the
          // actually-visible canvas area.
          _canvasSize = constraints.biggest;
          return _buildCanvasStack(context, isDark, bgColor);
        },
      ),
    );

    if (_isFullScreenMode) {
      // Matches whichever edge the toolbar was already docked to -- the
      // pull-handle and reveal direction follow `_toolbarOnLeft` instead
      // of always defaulting to the top.
      final Widget slidingToolbar = AnimatedSlide(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        offset: _toolbarRevealedInFullScreen
            ? Offset.zero
            : (_toolbarOnLeft ? const Offset(-1.2, 0) : const Offset(0, -1.2)),
        child: _toolbarOnLeft
            ? RotatedBox(quarterTurns: 1, child: _buildToolbar(context, isDark))
            : _buildToolbar(context, isDark),
      );
      final Widget handle = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(
          () => _toolbarRevealedInFullScreen = !_toolbarRevealedInFullScreen,
        ),
        child: Container(
          width: _toolbarOnLeft ? 5 : 48,
          height: _toolbarOnLeft ? 48 : 5,
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : Colors.black).withValues(
              alpha: 0.28,
            ),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      );

      return Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _canvasSize = constraints.biggest;
                return _buildCanvasStack(context, isDark, bgColor);
              },
            ),
          ),
          // The full toolbar -- hidden off-screen by default, sliding into
          // view when the pull-handle is tapped, instead of permanently
          // costing any canvas space. Positioned just clear of the
          // always-visible handle strip so the two never overlap once
          // revealed.
          if (_toolbarOnLeft)
            Positioned(top: 0, bottom: 0, left: 22, child: slidingToolbar)
          else
            Positioned(left: 0, right: 0, top: 22, child: slidingToolbar),
          // Small always-visible pull-handle standing in for the topbar --
          // tap to reveal/hide the full toolbar.
          if (_toolbarOnLeft)
            Positioned(top: 0, bottom: 0, left: 8, child: Center(child: handle))
          else
            Positioned(left: 0, right: 0, top: 8, child: Center(child: handle)),
          // Color palette sliding out from behind the quick tools.
          // Positioned at the root stack level rather than inside a bounded inner stack
          // so that flutter's hit testing correctly registers taps on it even when
          // it animates upward (otherwise hits fall through to the canvas below).
          AnimatedPositioned(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutBack,
            left: 0,
            right: 0,
            bottom: _quickToolsExpanded ? 84 : 26,
            child: AnimatedScale(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutBack,
              scale: _quickToolsExpanded ? 1.0 : 0.0,
              alignment: Alignment.bottomCenter,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: _quickToolsExpanded ? 1.0 : 0.0,
                child: IgnorePointer(
                  ignoring: !_quickToolsExpanded,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: _buildQuickColorsArc(isDark),
                  ),
                ),
              ),
            ),
          ),
          // Floating glass quick-tools box -- bottom-centre, clear of the
          // pull-handle above regardless of which edge it's docked to.
          // Centering it here (rather than pinning to one side) is what
          // makes the expand animation below grow outward in both
          // directions instead of just widening off to one side.
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: _buildFullScreenQuickTools(isDark),
            ),
          ),
        ],
      );
    }
    if (_toolbarOnLeft) {
      return Row(
        children: [
          // Same 90° clockwise rotation as before -- it's what keeps the
          // button order reading top-to-bottom (matching the un-rotated
          // layout) instead of reversing it. `_buildToolbar` itself builds
          // its rounded-corner/border decoration pre-inverted when
          // `_toolbarOnLeft` is true specifically so that, after this same
          // rotation, the corners/border land correctly for a left dock
          // (rounded on the outer left edge, bordered on the canvas-facing
          // right edge) instead of needing a different rotation direction
          // that would reverse the button order to get there.
          RotatedBox(quarterTurns: 1, child: _buildToolbar(context, isDark)),
          canvasArea,
        ],
      );
    }
    return Column(
      children: [
        // Whiteboard Header Controls Toolbar
        _buildToolbar(context, isDark),
        canvasArea,
      ],
    );
  }

  Widget _buildQuickColorsArc(bool isDark) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark
            ? _darkPanelColor.withValues(alpha: 0.85)
            : Colors.white.withValues(alpha: 0.85),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(50),
          bottom: Radius.circular(12),
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.2 : 0.6),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _palette.map((color) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: GestureDetector(
              onTap: () {
                if (_selectedLines.isNotEmpty) {
                  _recolorSelectedLines(color);
                  setState(() => _selectedColor = color);
                } else if (_selectedTextLabelIndex != null) {
                  setState(() {
                    _textLabels[_selectedTextLabelIndex!].color = color;
                    _selectedColor = color;
                  });
                } else {
                  setState(() {
                    _selectedColor = color;
                    _toolMode = CanvasToolMode.pen;
                    _activeShapeTool = null;
                    _isMagicPenMode = false;
                  });
                }
              },
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white,
                    width: _selectedColor.value == color.value ? 2.5 : 1.5,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Full-screen-only floating quick-tools bubble, styled like Apple's
  /// frosted "liquid glass" -- a small translucent blurred droplet that
  /// widens into a pill of a few essentials (pen, lasso, 3 quick colours,
  /// undo) when tapped, so the tutor doesn't have to pull the whole
  /// toolbar into view for the handful of actions used most while
  /// actively teaching. Collapsed and expanded states each own their tap
  /// target directly (rather than one wrapping the other) so a tap on an
  /// inner button while expanded can't also re-trigger the outer toggle.
  Widget _buildFullScreenQuickTools(bool isDark) {
    final Color iconColor = isDark ? Colors.white : _darkPanelColor;

    Widget glassShell({required double width, required Widget child}) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            width: width,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        Colors.white.withValues(alpha: 0.22),
                        Colors.white.withValues(alpha: 0.06),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.55),
                        Colors.white.withValues(alpha: 0.22),
                      ],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: isDark ? 0.28 : 0.65),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: child,
          ),
        ),
      );
    }

    Widget animatedTool(Widget child, int distance) {
      final double delayMs = distance * 50.0;
      final double totalDurationMs = 500.0;
      final double startFraction = delayMs / totalDurationMs;

      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: Duration(milliseconds: totalDurationMs.toInt()),
        curve: Interval(startFraction, 1.0, curve: Curves.easeOutBack),
        builder: (context, value, child) {
          return Transform.translate(
            offset: Offset(0, -40 * (1 - value)),
            child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
          );
        },
        child: child,
      );
    }

    // The box toggle itself -- centre element both collapsed and expanded,
    // so the container growing wider around it (it's laid out via
    // `Center` at the call site) reads as tools sliding out to either
    // side of the box rather than the box itself moving.
    final Widget box = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _quickToolsExpanded = !_quickToolsExpanded),
      onLongPress: () => setState(() {
        _isFullScreenMode = false;
        _toolbarRevealedInFullScreen = false;
        widget.onCanvasOnlyModeChanged?.call(false);
      }),
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          color: _quickToolsExpanded
              ? const Color(0xFF6366F1).withValues(alpha: 0.85)
              : Colors.transparent,
        ),
        child: Icon(
          Icons.crop_square_rounded,
          size: 20,
          color: _quickToolsExpanded ? Colors.white : iconColor,
        ),
      ),
    );

    if (!_quickToolsExpanded) {
      return glassShell(width: 56, child: box);
    }

    return glassShell(
      width: 380,
      // Clamped to its own full 380-wide layout regardless of what width
      // the AnimatedContainer above has actually reached at this frame --
      // it starts the 320ms width tween at 56 the instant this branch is
      // returned, so without this the Row (mainAxisSize.max, spaceEvenly)
      // would overflow every narrower in-between frame of the expand
      // animation, not just the very first one.
      child: OverflowBox(
        minWidth: 380,
        maxWidth: 380,
        minHeight: 56,
        maxHeight: 56,
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Left of the box.
            animatedTool(
              _quickToolIconButton(
                icon: _toolMode == CanvasToolMode.pen && _isMagicPenMode
                    ? Icons.auto_fix_high_rounded
                    : Icons.edit_rounded,
                iconColor: iconColor,
                isSelected: _toolMode == CanvasToolMode.pen,
                onTap: () => setState(() {
                  if (_toolMode == CanvasToolMode.pen &&
                      _activeShapeTool == null) {
                    _isMagicPenMode = !_isMagicPenMode;
                  } else {
                    _toolMode = CanvasToolMode.pen;
                    _activeShapeTool = null;
                  }
                }),
              ),
              4,
            ),
            animatedTool(
              _quickToolIconButton(
                icon: _eraserMode == EraserMode.stroke
                    ? Icons.auto_fix_high_rounded
                    : Icons.cleaning_services_rounded,
                iconColor: iconColor,
                isSelected: _toolMode == CanvasToolMode.eraser,
                onTap: () {
                  _activeShapeTool = null;
                  _handleEraserButtonTap();
                },
              ),
              3,
            ),
            animatedTool(
              _quickToolIconButton(
                icon: Icons.gesture_rounded,
                iconColor: iconColor,
                isSelected: _toolMode == CanvasToolMode.lasso,
                onTap: () => setState(() {
                  _toolMode = CanvasToolMode.lasso;
                  _activeShapeTool = null;
                  _selectedLines.clear();
                }),
              ),
              2,
            ),
            animatedTool(
              _quickToolIconButton(
                icon: Icons.center_focus_strong_rounded,
                iconColor: iconColor,
                isSelected: _toolMode == CanvasToolMode.laser,
                onTap: () => setState(() {
                  _toolMode = CanvasToolMode.laser;
                  _activeShapeTool = null;
                  _selectedLines.clear();
                }),
              ),
              1,
            ),
            box,
            // Right of the box.
            animatedTool(
              _quickToolIconButton(
                icon: Icons.format_color_fill_rounded,
                iconColor: iconColor,
                isSelected: _toolMode == CanvasToolMode.fill,
                onTap: () => setState(() {
                  _toolMode = CanvasToolMode.fill;
                  _activeShapeTool = null;
                  _selectedLines.clear();
                }),
              ),
              1,
            ),
            animatedTool(
              _quickToolIconButton(
                icon: Icons.back_hand_rounded,
                iconColor: iconColor,
                isSelected: _toolMode == CanvasToolMode.pan,
                onTap: () => setState(() {
                  _toolMode = CanvasToolMode.pan;
                  _activeShapeTool = null;
                  _selectedLines.clear();
                }),
              ),
              2,
            ),
            animatedTool(
              _quickToolIconButton(
                icon: Icons.unfold_more_rounded,
                iconColor: iconColor,
                isSelected: _toolMode == CanvasToolMode.spacer,
                onTap: () => setState(() {
                  if (_toolMode == CanvasToolMode.spacer) {
                    _compressCanvasSpace();
                  } else {
                    _toolMode = CanvasToolMode.spacer;
                  }
                  _activeShapeTool = null;
                  _selectedLines.clear();
                }),
              ),
              3,
            ),
            animatedTool(
              _quickToolIconButton(
                icon: Icons.undo_rounded,
                iconColor: iconColor,
                isSelected: false,
                onTap: _undo,
              ),
              4,
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickToolIconButton({
    required IconData icon,
    required Color iconColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected
              ? const Color(0xFF6366F1).withValues(alpha: 0.85)
              : Colors.transparent,
        ),
        child: Icon(
          icon,
          size: 17,
          color: isSelected ? Colors.white : iconColor,
        ),
      ),
    );
  }

  Widget _buildCanvasStack(BuildContext context, bool isDark, Color bgColor) {
    return ClipRRect(
      // Full screen: the canvas touches all four edges of the
      // outer rounded container directly (no adjacent toolbar
      // edge left flat), so every corner rounds.
      borderRadius: _isFullScreenMode
          ? const BorderRadius.all(Radius.circular(18))
          : (_toolbarOnLeft
                ? const BorderRadius.horizontal(right: Radius.circular(18))
                : const BorderRadius.vertical(bottom: Radius.circular(18))),
      child: Stack(
        children: [
          _buildCanvasCaptureArea(context, isDark, bgColor),
          if (_recordingState == MathPadRecordingState.recording)
            _RecordingNeonBorder(showCameraIcon: _recordWithCamera),
          if (_recordingState != MathPadRecordingState.idle)
            _buildRecordingBadge(context),
        ],
      ),
    );
  }

  Widget _buildRecordingBadge(BuildContext context) {
    // Listens to `_recordingService` directly instead of reading this
    // page's own state -- the elapsed-time text below changes once a
    // second for the entire length of a recording, and routing that
    // through this page's `setState` (as it used to) meant a full
    // canvas/toolbar rebuild every single second, competing with pointer/
    // stylus handling on the same UI isolate. Scoping the listener to just
    // this small badge keeps that once/sec update from touching anything
    // else.
    return ListenableBuilder(
      listenable: _recordingService,
      builder: (context, _) {
        final MathPadRecordingState state = _recordingService.state;
        final double encodingProgress = _recordingService.encodingProgress;
        // `waitingForEncodeChoice` is just a brief transitional tick
        // between `stopCapture()` returning and `encode()` starting --
        // there's no decision to wait on any more, so it shares the same
        // spinner treatment as `encoding` rather than getting its own
        // badge state.
        final bool busy =
            state == MathPadRecordingState.encoding ||
            state == MathPadRecordingState.waitingForEncodeChoice;

        final Widget badgeContent = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                  value: encodingProgress > 0 ? encodingProgress : null,
                ),
              )
            else
              const Icon(
                Icons.fiber_manual_record_rounded,
                size: 14,
                color: Colors.redAccent,
              ),
            const SizedBox(width: 8),
            Text(
              busy
                  ? (encodingProgress > 0
                        ? '${_recordingService.encodingPhaseLabel} '
                              '${(encodingProgress * 100).clamp(0, 100).toStringAsFixed(0)}%'
                        : _recordingService.encodingPhaseLabel)
                  : 'REC ${_formatRecordingElapsed(_recordingService.elapsed)}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        );

        return Positioned(
          top: 16,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: badgeContent,
            ),
          ),
        );
      },
    );
  }

  /// Everything actually captured into the recorded video -- kept as its
  /// own `RepaintBoundary` (distinct from the inner "Layer 1" one below,
  /// which exists purely as a repaint-scoping optimization) so
  /// `MathPadRecordingService` can snapshot exactly what's on the board
  /// and nothing else (not the REC badge above, not the toolbar, not other
  /// windows).
  Widget _buildCanvasCaptureArea(
    BuildContext context,
    bool isDark,
    Color bgColor,
  ) {
    return RepaintBoundary(
      key: _canvasCaptureKey,
      child: Stack(
        children: [
          // Guaranteed full-bleed opaque backdrop so the recorder's capture
          // (a single `toImage()` snapshot of this whole RepaintBoundary)
          // never contains a transparent pixel -- previously that showed up
          // as a black background in recorded video since video has no
          // alpha channel. Painting it here, as the actual bottom Stack
          // layer, fixes it at the source instead of the recorder having to
          // re-composite every captured frame over a background colour
          // after the fact, which was costing a second full rasterization
          // pass per frame and made it harder to sustain a high fps.
          // Skipped for `isTransparentBg` (used to composite the live
          // widget over something else, e.g. the slide viewer) since that
          // use case wants real transparency, not a recording-friendly one.
          if (!widget.isTransparentBg)
            Positioned.fill(child: ColoredBox(color: bgColor)),

          // Jyamiti Empty Canvas Watermark
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _finishedStrokesNotifier,
                  _activeDrawingNotifier,
                ]),
                builder: (_, __) {
                  return Center(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeInOut,
                      opacity:
                          (_lines.isEmpty &&
                              _textLabels.isEmpty &&
                              _instruments.isEmpty &&
                              _currentLine == null)
                          ? (isDark ? 0.2 : 0.12)
                          : 0.0,
                      child: Image.asset(
                        'assets/image/logo.png',
                        width: 240,
                        height: 240,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          MouseRegion(
            cursor: _canvasCursor,
            child: Listener(
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerCancel,
              onPointerSignal: _onPointerSignal,
              onPointerHover: _onPointerHover,
              // Trackpad-driven pan/zoom -- handled directly here instead of
              // through `GestureDetector`'s auto-synthesized `onScaleUpdate`
              // (see `_onScaleUpdate`'s doc comment for why: its synthesized
              // focal point drifts away from the true cursor position for
              // trackpad input). `event.localPosition` is the stable cursor
              // position (fixed for the whole gesture on a trackpad, unlike
              // an actual multi-touch pinch), `event.pan` is the raw
              // translation and `event.scale` the cumulative zoom, both
              // reliable straight from the platform.
              onPointerPanZoomStart: _onTrackpadPanZoomStart,
              onPointerPanZoomUpdate: _onTrackpadPanZoomUpdate,
              onPointerPanZoomEnd: _onTrackpadPanZoomEnd,
              child: GestureDetector(
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                onScaleEnd: _onScaleEnd,
                // Layer 0 (Grid Background): cheap, tracks pan/zoom live.
                // Layer 1 (Finished Strokes, 1a baked + 1b recent): positioned
                // via a single ancestor `Transform` so panning/zooming is a
                // GPU compositor op, NOT a Skia repaint of potentially a
                // page's whole ink history -- see the Layer 1 comment below.
                // Layer 2 (Active Drawing): repaints live stroke overlay,
                // still needs live pan/scale every frame, but its own content
                // is always small/bounded so that stays cheap.
                child: Stack(
                  children: [
                    // Layer 0: grid/ruled background pattern.
                    ValueListenableBuilder<Offset>(
                      valueListenable: _panNotifier,
                      builder: (_, pan, child) {
                        return ValueListenableBuilder<double>(
                          valueListenable: _scaleNotifier,
                          builder: (_, sc, child) {
                            return RepaintBoundary(
                              child: CustomPaint(
                                size: Size.infinite,
                                painter: _MathsPadGridBackgroundPainter(
                                  bgMode: _bgMode,
                                  isDark: isDark,
                                  panOffset: pan,
                                  scale: sc,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),

                    // Layer 1a+1b+2: baked chunks, the "recent" tail, AND the
                    // live active-drawing overlay, all sharing ONE `Transform`.
                    // Each of these three was at some point built with its
                    // OWN separate `Transform` instance (even though all
                    // three always read the same `_panNotifier`/
                    // `_scaleNotifier` values) -- every such split is a real
                    // opportunity for a frame to land with one updated and
                    // another not, and a stroke transitions from being drawn
                    // live on Layer 2 to being rendered as committed ink on
                    // Layer 1b in a SINGLE frame, right when the pen lifts --
                    // exactly where any mismatch between separate Transforms
                    // would show up as ink visibly popping to a slightly
                    // different position the instant it's drawn (confirmed:
                    // this happened on every single stroke once Layer 1a/1b
                    // moved off Layer 2's original CPU-canvas-transform
                    // mechanism onto a GPU `TransformLayer`, and persisted
                    // even after merging 1a+1b alone, until Layer 2 joined
                    // them here too). Sharing one `Transform` for all three
                    // makes that structurally impossible -- they're pixel-
                    // identical by construction, not just by coincidence of
                    // observing equal notifier values. Layer 1b/2's inner
                    // `ValueListenableBuilder`s technically rebuild on every
                    // pan/zoom frame now too, but `shouldRepaint`'s
                    // `identical()` check (Layer 1b) and Layer 2's inherently
                    // small/bounded content mean that costs nothing beyond
                    // constructing a few Dart objects -- no real extra
                    // repaint work.
                    ValueListenableBuilder<Offset>(
                      valueListenable: _panNotifier,
                      builder: (_, pan, child) {
                        return ValueListenableBuilder<double>(
                          valueListenable: _scaleNotifier,
                          builder: (_, sc, child) {
                            // A generous pre-render margin (a full screen's
                            // worth on every side, not just a small fixed
                            // padding) for Layer 1a's viewport culling below
                            // -- zooming OUT rapidly expands the viewport, so
                            // without a wide margin many previously
                            // off-screen chunks can all flip to "visible"
                            // (and pay their one-time real render cost) in
                            // the same final frame right as the gesture
                            // settles, which looks like a delay right after
                            // zoom. Pre-rendering chunks well before they'd
                            // actually enter view spreads that cost across
                            // earlier frames instead of concentrating it at
                            // the end.
                            final Rect viewport = Rect.fromLTWH(
                              -pan.dx / sc,
                              -pan.dy / sc,
                              _canvasSize.width / sc,
                              _canvasSize.height / sc,
                            ).inflate(_canvasSize.longestSide / sc);
                            return Transform(
                              transform: Matrix4.identity()
                                ..translate(pan.dx, pan.dy)
                                ..scale(sc),
                              child: Stack(
                                children: [
                                  // Layer 1a: "Baked" finished strokes -- one
                                  // keyed RepaintBoundary PER SEALED CHUNK
                                  // (`_bakedChunks`), permanently mounted
                                  // (same `ValueKey`s, list length never
                                  // shrinks) -- an earlier version instead
                                  // excluded off-screen chunks from the
                                  // `Stack`'s children entirely, which meant
                                  // destroying and recreating a chunk's GPU
                                  // layer every time it crossed the viewport
                                  // edge; that churn caused a delayed
                                  // "everything freezes for a stretch" stall.
                                  // `isVisible` lets `_MathsPadFinishedStrokes
                                  // Painter.paint` skip its real work (Skia
                                  // recomputing anti-aliased stroke edges on
                                  // a scale change) for off-screen chunks
                                  // without ever touching mount state.
                                  ValueListenableBuilder<int>(
                                    valueListenable: _bakedStrokesNotifier,
                                    builder: (_, _, _) {
                                      return Stack(
                                        children: [
                                          for (
                                            int c = 0;
                                            c < _bakedChunks.length;
                                            c++
                                          )
                                            RepaintBoundary(
                                              key: ValueKey('baked_chunk_$c'),
                                              child: CustomPaint(
                                                size: Size.infinite,
                                                painter:
                                                    _MathsPadFinishedStrokesPainter(
                                                      lines: _bakedChunks[c],
                                                      isVisible:
                                                          _bakedChunkBounds[c]
                                                              .overlaps(
                                                                viewport,
                                                              ),
                                                      allSelectedLines:
                                                          _selectedLines,
                                                    ),
                                              ),
                                            ),
                                        ],
                                      );
                                    },
                                  ),

                                  // Layer 1b: "Recent" finished strokes -- the
                                  // small tail not yet folded into a baked
                                  // chunk; always bounded to at most
                                  // `_kBakeThreshold` lines regardless of
                                  // page size, so it never needs viewport
                                  // culling of its own.
                                  ValueListenableBuilder<int>(
                                    valueListenable: _finishedStrokesNotifier,
                                    builder: (_, _, _) {
                                      return RepaintBoundary(
                                        child: CustomPaint(
                                          size: Size.infinite,
                                          painter:
                                              _MathsPadFinishedStrokesPainter(
                                                lines: _lines.sublist(
                                                  _bakedLineCount.clamp(
                                                    0,
                                                    _lines.length,
                                                  ),
                                                ),
                                                allSelectedLines:
                                                    _selectedLines,
                                              ),
                                        ),
                                      );
                                    },
                                  ),

                                  // Layer 2: Active Drawing Overlay &
                                  // Handles -- merged into this SAME shared
                                  // `Transform` (rather than its own separate
                                  // one) for the same reason Layer 1a/1b were
                                  // merged: this is exactly where the live
                                  // in-progress stroke is drawn right up
                                  // until the instant it's committed and
                                  // handed off to Layer 1b, so any
                                  // possibility of these two using even
                                  // very-slightly different transforms is
                                  // exactly what would show up as a stroke
                                  // visibly popping to a different position
                                  // right when the pen lifts. Its own content
                                  // is always small/bounded, so still cheap
                                  // to redraw every frame even though it's
                                  // now inside the same rebuild-on-pan/zoom
                                  // subtree as Layer 1a.

                                  // Layer 2a: baked-so-far snapshot of the
                                  // CURRENTLY in-progress stroke -- see
                                  // `_kLiveBakeEvery`'s doc comment. Fixes
                                  // "writing a long line/sentence gets
                                  // progressively slower the longer it
                                  // runs" -- without this, Layer 2 below had
                                  // to rebuild+rerasterize the WHOLE
                                  // stroke-so-far every single frame.
                                  ValueListenableBuilder<int>(
                                    valueListenable: _activeDrawingNotifier,
                                    builder: (_, _, _) {
                                      return RepaintBoundary(
                                        child: CustomPaint(
                                          size: Size.infinite,
                                          painter:
                                              _MathsPadLiveStrokeBakedPainter(
                                                line: _currentLine,
                                                bakedPointCount:
                                                    _currentLine
                                                        ?.liveBakedPointCount ??
                                                    0,
                                              ),
                                        ),
                                      );
                                    },
                                  ),

                                  ValueListenableBuilder<int>(
                                    valueListenable: _activeDrawingNotifier,
                                    builder: (_, _, _) {
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
                                                laserTrail: _laserTrail,
                                                selectionGlowPhase:
                                                    _selectionGlowPhase,
                                                eraserCursorPos:
                                                    _eraserCursorPos,
                                                eraserCursorRadius:
                                                    _eraserWidth * 1.75,
                                                isRecording:
                                                    _recordingState == MathPadRecordingState.recording,
                                              ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ), // Close MouseRegion
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
                !_textEditorOpen &&
                _pastePopupWorldPos == null,
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
                      child: _UnconstrainedHitTestStack(
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
                                  (_angleOtherEndOfA! - _angleVertex!)
                                      .direction,
                                  (_angleLiveEnd! - _angleVertex!).direction,
                                ),
                              ),
                              '${_angleLiveDegrees!.toStringAsFixed(1)}°',
                              live: true,
                            ),
                          if (_toolMode == CanvasToolMode.polygonAngle &&
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
                                  (_polygonVertices[_polygonVertices.length -
                                              2] -
                                          _polygonVertices.last)
                                      .direction,
                                  (_polygonLiveEnd! - _polygonVertices.last)
                                      .direction,
                                ),
                              ),
                              '${_polygonLiveDegrees!.toStringAsFixed(1)}°',
                              live: true,
                            ),
                          if (_toolMode == CanvasToolMode.polygonAngle &&
                              _currentLine != null &&
                              _polygonLiveEnd != null)
                            _buildAngleBadge(
                              _perpendicularMidpoint(
                                _currentLine!.points.first.offset,
                                _polygonLiveEnd!,
                                20,
                              ),
                              '${((_polygonLiveEnd! - _currentLine!.points.first.offset).distance / kPxPerCm).toStringAsFixed(1)} cm',
                              live: true,
                            ),
                          if (_toolMode == CanvasToolMode.circleArc &&
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
                          if (_toolMode == CanvasToolMode.square &&
                              _squareBaseStart != null &&
                              _squareBaseEnd != null &&
                              !_squareHasArmed)
                            _buildAngleBadge(
                              _perpendicularMidpoint(
                                _squareBaseStart!,
                                _squareBaseEnd!,
                                20,
                              ),
                              '${((_squareBaseEnd! - _squareBaseStart!).distance / kPxPerCm).toStringAsFixed(1)} cm',
                              live: true,
                            ),
                          if (_toolMode == CanvasToolMode.straightLine &&
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
                                        Offset(24, _spacerLiveShift / 2)
                                  : _spacerDrag!.startWorld +
                                        Offset(_spacerLiveShift / 2, 24),
                              '${(_spacerLiveShift / kPxPerCm).toStringAsFixed(1)} cm',
                              live: true,
                            ),
                          ..._textLabels.asMap().entries.map(
                            (e) => _buildTextLabelWidget(e.key, e.value),
                          ),
                          _buildTextEditorOverlay(isDark),
                          _buildPastePopup(isDark),
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

              final String effectiveQText = widget.questionText!.trim();

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
                      color: (isDark ? _darkPanelColor : Colors.white)
                          .withOpacity(0.95),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF6366F1).withOpacity(0.5),
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
                                borderRadius: BorderRadius.circular(8),
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
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                  size: 20,
                                  color: _textColor60,
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
                              color: _textColor,
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

          // Ruler/Protractor: a magnified loupe near the pencil while it's
          // being dragged -- shows a real zoomed view of the canvas right
          // at the pencil's exact position (which the finger/stylus
          // touching it usually obscures), with the live length/angle
          // overlaid in the loupe's own bottom-right corner. Built with the
          // framework's own `RawMagnifier` (the same widget that powers
          // text-selection loupes) via `BackdropFilter`, so it's a genuine
          // magnification of whatever's actually composited on screen --
          // not a hand-drawn approximation -- and correctly tracks the
          // canvas's own pan/zoom for free. Deliberately placed OUTSIDE the
          // canvas's pan/zoom `Transform` above (in screen space) so the
          // loupe itself stays a constant on-screen size regardless of
          // canvas zoom level, same reasoning as the selection handles.
          if ((_draggedInstrument is RulerState ||
                  _draggedInstrument is ProtractorState) &&
              _draggedHandle == 'pencil')
            Builder(
              builder: (context) {
                final InstrumentState inst = _draggedInstrument!;
                final Offset pencilWorldPos =
                    inst.handleWorldPositions()['pencil']!;
                final Offset pencilScreenPos =
                    pencilWorldPos * _scale + _panOffset;

                // Larger loupe + lower magnificationScale = same apparent
                // field-of-view but each screen pixel in the loupe covers a
                // smaller area of the source, giving noticeably sharper
                // content (especially on hi-DPI displays). 200px at 1.8x is
                // visually equivalent to 150px at 2.2x but much crisper.
                const double magnifierSize = 200;
                // Floats the loupe up and to the side of the pencil (along
                // the instrument's own perpendicular) so the hand/stylus
                // actually touching the pencil doesn't cover the loupe
                // showing it.
                final Offset dir = inst.rotatedLocal(1, 0) - inst.pivot;
                final double dirLen = dir.distance;
                final Offset normal = dirLen > 0
                    ? Offset(-dir.dy, dir.dx) / dirLen
                    : const Offset(0, -1);
                final Offset loupeCenterScreen =
                    pencilScreenPos + normal * -130;

                // Whole degrees only, matching the pencil's own snapped
                // movement (see `_updateInstrumentDrag`'s pencil branch) --
                // it's always already an integer, so no decimal point.
                final String measurementText = inst is RulerState
                    ? _rulerLiveLengthText(inst)
                    : '${(-(inst as ProtractorState).pencilAngle * 180 / pi).round()}°';

                return Positioned(
                  left: loupeCenterScreen.dx - magnifierSize / 2,
                  top: loupeCenterScreen.dy - magnifierSize / 2,
                  child: IgnorePointer(
                    child: RawMagnifier(
                      size: const Size(magnifierSize, magnifierSize),
                      // 1.8x at 200px ≈ 2.2x at 150px in field-of-view, but
                      // sharper: less upscaling per source pixel.
                      magnificationScale: 1.8,
                      // Tells the loupe to show the content AT the pencil's
                      // screen position even though the loupe itself is
                      // rendered offset away from it -- see the field's own
                      // doc comment for the exact formula.
                      focalPointOffset: pencilScreenPos - loupeCenterScreen,
                      decoration: MagnifierDecoration(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: const BorderSide(
                            color: Color(0xFF2563EB),
                            width: 2.5,
                          ),
                        ),
                        shadows: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      // antiAlias gives smooth rounded corners at any DPI,
                      // hardEdge was aliased/jagged on hi-DPI displays.
                      clipBehavior: Clip.antiAlias,
                      child: Align(
                        alignment: Alignment.bottomRight,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2563EB),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              measurementText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
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
              bottom: (widget.isFullScreen || _isFullScreenMode) ? null : 16,
              top: (widget.isFullScreen || _isFullScreenMode) ? 16 : null,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? _darkPanelColor : Colors.white,
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
                          color: _textColor,
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
                      // Bring to Front / Send to Back -- only shown when
                      // the selection includes a pasted image (see
                      // `_bringSelectedToFront`'s doc comment for why
                      // reordering is meaningless for a Fill Tool
                      // result, always forced to the very bottom
                      // regardless).
                      if (_selectedLines.any((l) => l.isPastedImage)) ...[
                        const SizedBox(width: 6),
                        Tooltip(
                          message: 'Bring to Front',
                          child: IconButton(
                            icon: const Icon(Icons.flip_to_front, size: 18),
                            onPressed: _bringSelectedToFront,
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(6),
                            color: _textColor70,
                          ),
                        ),
                        Tooltip(
                          message: 'Send to Back',
                          child: IconButton(
                            icon: const Icon(Icons.flip_to_back, size: 18),
                            onPressed: _sendSelectedToBack,
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(6),
                            color: _textColor70,
                          ),
                        ),
                      ],
                      // Stick/Unstick Drawings To Image -- only shown when
                      // exactly ONE pasted image is selected (see
                      // `_toggleStickDrawingsToImage`'s doc comment for
                      // why it needs a single clear "target" image). The
                      // pin fills in once stuck, so its own state doubles
                      // as the toggle's current status at a glance.
                      if (_selectedLines.length == 1 &&
                          _selectedLines.first.isPastedImage) ...[
                        const SizedBox(width: 6),
                        Tooltip(
                          message: _selectedImageIsStuck
                              ? 'Unstick Drawings From Image'
                              : 'Stick Drawings To Image',
                          child: IconButton(
                            icon: Icon(
                              _selectedImageIsStuck
                                  ? Icons.push_pin_rounded
                                  : Icons.push_pin_outlined,
                              size: 18,
                            ),
                            onPressed: _toggleStickDrawingsToImage,
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(6),
                            color: _selectedImageIsStuck
                                ? const Color(0xFF6366F1)
                                : _textColor70,
                          ),
                        ),
                      ],
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
                        icon: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: _textColor70,
                        ),
                        onPressed: () => setState(() => _selectedLines.clear()),
                        tooltip: 'Deselect',
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Right Side Tools (Asset Library, Spinner, Graphing)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInCubic,
            right: _isRightToolbarVisible ? 16 : -100,
            top: 100,
            child: MouseRegion(
              onEnter: (_) => _keepRightToolbarOpen(),
              onExit: (_) => _startRightToolbarHideTimer(),
              child: Listener(
                onPointerDown: (_) {
                  _keepRightToolbarOpen();
                  _startRightToolbarHideTimer();
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildAssetLibraryToolbarButton(),
                    const SizedBox(height: 8),
                    _buildSpinnerToolbarButton(),
                    const SizedBox(height: 8),
                    _buildEquationToolbarButton(),
                    const SizedBox(height: 8),
                    _buildGraphingToolbarButton(),
                    const SizedBox(height: 8),
                    _buildPdfExportToolbarButton(),
                  ],
                ),
              ),
            ),
          ),

          if (!_isRightToolbarVisible)
            Positioned(
              right: 0,
              top: 100,
              width: 40,
              height: 300,
              child: MouseRegion(
                onEnter: (_) {
                  _rightToolbarHoverTimer?.cancel();
                  _rightToolbarHoverTimer = Timer(
                    const Duration(seconds: 3),
                    () {
                      _keepRightToolbarOpen();
                      _startRightToolbarHideTimer();
                    },
                  );
                },
                onExit: (_) {
                  _rightToolbarHoverTimer?.cancel();
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    _keepRightToolbarOpen();
                    _startRightToolbarHideTimer();
                  },
                  child: const SizedBox(width: 40, height: 300),
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
                  color: (isDark ? Colors.black : Colors.white).withOpacity(
                    0.75,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: (isDark ? Colors.white : Colors.black).withOpacity(
                      0.1,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('assets/image/logo.png', height: 20, width: 20),
                    Icon(
                      _toolMode == CanvasToolMode.eraser
                          ? (_eraserMode == EraserMode.stroke
                                ? Icons.auto_fix_high_rounded
                                : Icons.cleaning_services_rounded)
                          : (_toolMode == CanvasToolMode.tapSelect
                                ? Icons.touch_app_rounded
                                : (_toolMode == CanvasToolMode.lasso
                                      ? Icons.gesture_rounded
                                      : (_toolMode == CanvasToolMode.pan
                                            ? Icons.back_hand_rounded
                                            : (_toolMode ==
                                                      CanvasToolMode.pencil
                                                  ? Icons.draw_rounded
                                                  : Icons.edit_rounded)))),
                      size: 14,
                      color: _textColor70,
                    ),
                    const SizedBox(width: 4),
                    ValueListenableBuilder<double>(
                      valueListenable: _scaleNotifier,
                      builder: (_, sc, _c) {
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _toolMode == CanvasToolMode.eraser
                                  ? (_eraserMode == EraserMode.stroke
                                        ? 'Stroke Eraser • Tap any stroke to erase whole line'
                                        : 'Area Eraser • Drag to erase points')
                                  : (_toolMode == CanvasToolMode.tapSelect
                                        ? 'Tap any line to select & move/duplicate'
                                        : (_toolMode == CanvasToolMode.lasso
                                              ? 'Draw loop around items to select & move/duplicate'
                                              : (_toolMode ==
                                                        CanvasToolMode.pencil
                                                    ? 'Pencil • Pressure-Sensitive'
                                                    : 'Infinite Canvas'))),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _textColor70,
                              ),
                            ),
                            if (_toolMode != CanvasToolMode.eraser &&
                                _toolMode != CanvasToolMode.tapSelect &&
                                _toolMode != CanvasToolMode.lasso) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _isDarkTheme
                                      ? Colors.white.withOpacity(0.05)
                                      : Colors.black.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    InkWell(
                                      onTap: _zoomOut,
                                      borderRadius: BorderRadius.circular(4),
                                      child: Padding(
                                        padding: const EdgeInsets.all(2.0),
                                        child: Icon(
                                          Icons.zoom_out_rounded,
                                          size: 14,
                                          color: _textColor,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Tooltip(
                                      message: _zoomLocked
                                          ? 'Zoom Locked (Long press to unlock)'
                                          : 'Reset Center & 100% Zoom (Long press to lock)',
                                      child: InkWell(
                                        onTap: _resetView,
                                        onLongPress: () {
                                          setState(() {
                                            _zoomLocked = !_zoomLocked;
                                          });
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                _zoomLocked
                                                    ? 'Zoom Locked'
                                                    : 'Zoom Unlocked',
                                              ),
                                              duration: const Duration(
                                                seconds: 2,
                                              ),
                                            ),
                                          );
                                        },
                                        borderRadius: BorderRadius.circular(4),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              '${(sc * 100).round()}%',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: _zoomLocked
                                                    ? Colors.redAccent
                                                    : _textColor,
                                              ),
                                            ),
                                            if (_zoomLocked) ...[
                                              const SizedBox(width: 2),
                                              const Icon(
                                                Icons.lock_rounded,
                                                size: 10,
                                                color: Colors.redAccent,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    InkWell(
                                      onTap: _zoomIn,
                                      borderRadius: BorderRadius.circular(4),
                                      child: Padding(
                                        padding: const EdgeInsets.all(2.0),
                                        child: Icon(
                                          Icons.zoom_in_rounded,
                                          size: 14,
                                          color: _textColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                    const SizedBox(width: 6),
                    // Pan-Direction Lock -- once on, panning/scrolling can
                    // only reveal more canvas below/to the right of
                    // wherever it was engaged, never back up/left past it
                    // (handy for not accidentally scrolling away from
                    // where you're currently writing). See
                    // `_clampPanIfLocked`'s doc comment.
                    Tooltip(
                      message: _panLocked
                          ? 'Pan Locked (tap to unlock) • can\'t scroll up/left'
                          : 'Lock Pan Direction • only allow scrolling down/right',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          setState(() {
                            _panLocked = !_panLocked;
                            _panLockWorldTopLeft = _panLocked
                                ? Offset(
                                    -_panOffset.dx / _scale,
                                    -_panOffset.dy / _scale,
                                  )
                                : null;
                          });
                          SharedPreferences.getInstance().then(
                            (prefs) =>
                                prefs.setBool('mathpad_pan_locked', _panLocked),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                _panLocked
                                    ? 'Pan Locked • can only scroll down/right'
                                    : 'Pan Unlocked',
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(
                            _panLocked
                                ? Icons.lock_rounded
                                : Icons.lock_open_rounded,
                            size: 14,
                            color: _panLocked ? Colors.redAccent : _textColor70,
                          ),
                        ),
                      ),
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
    int _animIconIndex = 0;
    Widget animated(Widget child) {
      final int currentIndex = _animIconIndex++;
      final int distance = (currentIndex - 7).abs();
      final double delayMs = distance * 40.0;
      final double totalDurationMs = 500.0;
      final double startFraction = (delayMs / totalDurationMs).clamp(0.0, 0.99);

      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: Duration(milliseconds: totalDurationMs.toInt()),
        curve: Interval(startFraction, 1.0, curve: Curves.easeOutBack),
        builder: (context, value, child) {
          return Transform.translate(
            offset: _toolbarOnLeft
                ? Offset(-40 * (1 - value), 0)
                : Offset(0, -40 * (1 - value)),
            child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
          );
        },
        child: child,
      );
    }

    // Left-docked also goes through quarterTurns:1 (same as right-docked
    // used to, and still does) so the button order always reads top-to-
    // bottom regardless of which side it's on -- but that rotation maps
    // pre-rotation TOP-rounded/BOTTOM-bordered into POST-rotation RIGHT-
    // rounded/LEFT-bordered (see `_buildToolbarAndCanvas`), which is
    // backwards for a left dock. Building it pre-inverted (rounded at the
    // bottom, bordered at the top) here compensates, so after that same
    // rotation it lands correctly: rounded on the left (outer edge),
    // bordered on the right (canvas-facing edge).
    final BorderRadius radius = _toolbarOnLeft
        ? const BorderRadius.vertical(bottom: Radius.circular(18))
        : const BorderRadius.vertical(top: Radius.circular(18));
    final BorderSide edgeBorder = BorderSide(
      color: isDark ? Colors.white10 : Colors.black12,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? _darkPanelColor : const Color(0xFFF1F5F9),
        borderRadius: radius,
        border: _toolbarOnLeft
            ? Border(top: edgeBorder)
            : Border(bottom: edgeBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.leadingToolbarAction != null) ...[
            RotatedBox(
              quarterTurns: _toolbarOnLeft ? -1 : 0,
              child: widget.leadingToolbarAction!,
            ),
            const SizedBox(width: 12),
            Container(
              width: 1,
              height: 32,
              color: isDark ? Colors.white24 : Colors.black12,
            ),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              // Clamp instead of the platform-default rubber-band/bounce physics
              // -- most noticeable (and worst-looking) when this toolbar is
              // rotated 90° into the left/right-docked layout, where scrolling
              // to reach more tools produces a visible bounce/overshoot instead
              // of stopping cleanly at the end of the row.
              physics: const ClampingScrollPhysics(),
              child: Row(
                children: [
                  // Pen, Stroke Eraser, Tap-to-Select, Lasso Select, & Pan Tool
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? _darkPillColor : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        animated(
                          _buildIconButton(
                            icon: Icons.edit_rounded,
                            tooltip: 'Pen Mode (Constant Width)',
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
                        ),
                        animated(
                          _buildIconButton(
                            icon: Icons.draw_rounded,
                            tooltip: 'Pencil Mode (Pressure-Sensitive)',
                            isSelected:
                                _toolMode == CanvasToolMode.pencil &&
                                _activeShapeTool == null,
                            onTap: () => setState(() {
                              _toolMode = CanvasToolMode.pencil;
                              _activeShapeTool = null;
                              _selectedWidth = _pencilWidth;
                              _selectedLines.clear();
                            }),
                          ),
                        ),
                        animated(
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
                        ),
                        animated(
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
                        ),
                        animated(
                          _buildIconButton(
                            icon: Icons.touch_app_rounded,
                            tooltip: 'Tap Line to Select, Move & Duplicate',
                            isSelected: _toolMode == CanvasToolMode.tapSelect,
                            onTap: () => setState(() {
                              _toolMode = CanvasToolMode.tapSelect;
                              _activeShapeTool = null;
                            }),
                          ),
                        ),
                        animated(
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
                            isSelected:
                                _toolMode == CanvasToolMode.straightLine,
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
                        ),
                        animated(
                          _buildIconButton(
                            icon: _toolMode == CanvasToolMode.polygonAngle
                                ? Icons.timeline_rounded
                                : Icons.call_split_rounded,
                            tooltip: _toolMode == CanvasToolMode.polygonAngle
                                ? 'Polygon Angle Tool: ACTIVE — tap icon again to '
                                      'switch back to Angle Tool'
                                : _toolMode == CanvasToolMode.angle
                                ? 'Angle Tool: ACTIVE — tap icon again to switch '
                                      'to Polygon Angle Tool'
                                : 'Angle Tool: draw a line, then drag a second '
                                      'line from either of its ends to see the '
                                      'angle between them live -- release to fix it '
                                      '(tap icon again while active to toggle '
                                      'Polygon Angle Tool)',
                            isSelected:
                                _toolMode == CanvasToolMode.angle ||
                                _toolMode == CanvasToolMode.polygonAngle,
                            onTap: () => setState(() {
                              if (_toolMode == CanvasToolMode.angle) {
                                // Toggle → Polygon Angle
                                _toolMode = CanvasToolMode.polygonAngle;
                                _activeShapeTool = null;
                                _selectedWidth = _penWidth;
                                _selectedLines.clear();
                                _resetPolygonTool();
                              } else if (_toolMode ==
                                  CanvasToolMode.polygonAngle) {
                                // Toggle back → Angle
                                _toolMode = CanvasToolMode.angle;
                                _activeShapeTool = null;
                                _selectedWidth = _penWidth;
                                _selectedLines.clear();
                                _resetAngleTool();
                              } else {
                                // First tap → Angle (default)
                                _toolMode = CanvasToolMode.angle;
                                _activeShapeTool = null;
                                _selectedWidth = _penWidth;
                                _selectedLines.clear();
                                _resetAngleTool();
                              }
                            }),
                          ),
                        ),
                        animated(
                          _buildIconButton(
                            icon: _toolMode == CanvasToolMode.square
                                ? Icons.crop_square_rounded
                                : Icons.blur_circular_rounded,
                            tooltip: _toolMode == CanvasToolMode.square
                                ? 'Square Tool: ACTIVE — tap icon again to switch back '
                                      'to Circle/Arc Tool'
                                : _toolMode == CanvasToolMode.circleArc
                                ? 'Circle/Arc Tool: ACTIVE — tap icon again to '
                                      'switch to Square Tool'
                                : 'Circle/Arc Tool: drag out to set the radius, '
                                      'then keep dragging in a curve around that '
                                      'same point — only the traced arc/circle '
                                      'stays when you release '
                                      '(tap icon again while active to toggle '
                                      'Square Tool)',
                            isSelected:
                                _toolMode == CanvasToolMode.circleArc ||
                                _toolMode == CanvasToolMode.square,
                            onTap: () => setState(() {
                              if (_toolMode == CanvasToolMode.circleArc) {
                                // Toggle → Square
                                _toolMode = CanvasToolMode.square;
                                _activeShapeTool = null;
                                _selectedWidth = _penWidth;
                                _selectedLines.clear();
                                _resetSquareTool();
                              } else if (_toolMode == CanvasToolMode.square) {
                                // Toggle back → Circle/Arc
                                _toolMode = CanvasToolMode.circleArc;
                                _activeShapeTool = null;
                                _selectedWidth = _penWidth;
                                _selectedLines.clear();
                                _resetCircleArcTool();
                              } else {
                                // First tap → Circle/Arc (default)
                                _toolMode = CanvasToolMode.circleArc;
                                _activeShapeTool = null;
                                _selectedWidth = _penWidth;
                                _selectedLines.clear();
                                _resetCircleArcTool();
                              }
                            }),
                          ),
                        ),
                        animated(
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
                        ),
                        animated(
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
                        ),

                        animated(
                          _buildIconButton(
                            icon: Icons.unfold_more_rounded,
                            tooltip:
                                'Spacer Tool: drag through a gap to push everything '
                                'past that point further away, live, opening up '
                                'blank space to work in (tap icon again to '
                                'compress whitespace)',
                            isSelected: _toolMode == CanvasToolMode.spacer,
                            onTap: () => setState(() {
                              if (_toolMode == CanvasToolMode.spacer) {
                                _compressCanvasSpace();
                              } else {
                                _toolMode = CanvasToolMode.spacer;
                              }
                              _activeShapeTool = null;
                              _selectedLines.clear();
                            }),
                          ),
                        ),

                        animated(
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
                        ),
                        animated(
                          _buildIconButton(
                            icon: Icons.center_focus_strong_rounded,
                            tooltip:
                                'Laser Pointer: hold and move to point things out '
                                'live -- leaves no permanent mark',
                            isSelected: _toolMode == CanvasToolMode.laser,
                            onTap: () => setState(() {
                              _toolMode = CanvasToolMode.laser;
                              _activeShapeTool = null;
                              _selectedLines.clear();
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Geometry Instruments: Ruler, Protractor, Compass, Set Squares
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? _darkPillColor : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        animated(
                          _buildIconButton(
                            icon: Icons.straighten_rounded,
                            tooltip: 'Add Ruler',
                            onTap: () => _addInstrument(
                              (i) => i is RulerState,
                              (center) => RulerState(pivot: center),
                            ),
                          ),
                        ),
                        animated(
                          _buildIconButton(
                            customIconBuilder: _buildProtractorIcon,
                            tooltip: 'Add Protractor',
                            onTap: () => _addInstrument(
                              (i) => i is ProtractorState,
                              (center) => ProtractorState(pivot: center),
                            ),
                          ),
                        ),
                        animated(
                          _buildIconButton(
                            icon: Icons.architecture_rounded,
                            tooltip: 'Add Compass',
                            onTap: () => _addInstrument(
                              (i) => i is CompassState,
                              (center) => CompassState(pivot: center),
                            ),
                          ),
                        ),
                        animated(
                          _buildIconButton(
                            icon: Icons.change_history_rounded,
                            tooltip: 'Add Set Square (45-45-90)',
                            onTap: () => _addInstrument(
                              (i) =>
                                  i is SetSquareState &&
                                  i.kind == SetSquareKind.fortyFive,
                              (center) => SetSquareState(
                                pivot: center,
                                kind: SetSquareKind.fortyFive,
                              ),
                            ),
                          ),
                        ),
                        animated(
                          _buildIconButton(
                            icon: Icons.change_history_outlined,
                            tooltip: 'Add Set Square (30-60-90)',
                            onTap: () => _addInstrument(
                              (i) =>
                                  i is SetSquareState &&
                                  i.kind == SetSquareKind.thirtySixty,
                              (center) => SetSquareState(
                                pivot: center,
                                kind: SetSquareKind.thirtySixty,
                              ),
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
                          (_toolMode == CanvasToolMode.pen ||
                              _toolMode == CanvasToolMode.pencil) &&
                          _activeShapeTool == null &&
                          _selectedColor.value == color.value;
                      return GestureDetector(
                        onTap: () {
                          // With something already selected, picking a colour
                          // recolours that selection in place instead of just
                          // arming the pen with it -- selection stays as-is
                          // (not cleared, tool mode untouched) so further
                          // actions (another colour, width, delete, ...) can
                          // still target the same selection right after.
                          if (_selectedLines.isNotEmpty) {
                            _recolorSelectedLines(color);
                            setState(() => _selectedColor = color);
                            return;
                          }
                          if (_selectedTextLabelIndex != null) {
                            setState(() {
                              _textLabels[_selectedTextLabelIndex!].color =
                                  color;
                              _selectedColor = color;
                            });
                            return;
                          }
                          setState(() {
                            _selectedColor = color;
                            // Preserve Pencil mode if already active;
                            // otherwise default back to the classic Pen.
                            if (_toolMode != CanvasToolMode.pencil) {
                              _toolMode = CanvasToolMode.pen;
                            }
                            _activeShapeTool = null;
                            _selectedWidth = _toolMode == CanvasToolMode.pencil
                                ? _pencilWidth
                                : _penWidth;
                            _isMagicPenMode = false;
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
                    icon: RotatedBox(
                      quarterTurns: _toolbarOnLeft ? -1 : 0,
                      child: Row(
                        children: [
                          Icon(
                            Icons.line_weight_rounded,
                            size: 18,
                            color: _textColor,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${_selectedWidth.toInt()}px',
                            style: TextStyle(fontSize: 11, color: _textColor),
                          ),
                        ],
                      ),
                    ),
                    color: isDark ? _darkPanelColor : Colors.white,
                    onSelected: (w) => setState(() {
                      _selectedWidth = w;
                      if (_toolMode == CanvasToolMode.eraser) {
                        _eraserWidth = w;
                      } else if (_toolMode == CanvasToolMode.pencil) {
                        _pencilWidth = w;
                      } else {
                        _penWidth = w;
                      }
                    }),
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 2.0,
                        child: Text(
                          'Fine (2px)',
                          style: TextStyle(color: _textColor),
                        ),
                      ),
                      PopupMenuItem(
                        value: 4.0,
                        child: Text(
                          'Medium (4px)',
                          style: TextStyle(color: _textColor),
                        ),
                      ),
                      PopupMenuItem(
                        value: 6.0,
                        child: Text(
                          'Bold (6px)',
                          style: TextStyle(color: _textColor),
                        ),
                      ),
                      PopupMenuItem(
                        value: 8.0,
                        child: Text(
                          'Thick (8px)',
                          style: TextStyle(color: _textColor),
                        ),
                      ),
                      PopupMenuItem(
                        value: 14.0,
                        child: Text(
                          'Marker (14px)',
                          style: TextStyle(color: _textColor),
                        ),
                      ),
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
                    color: isDark ? _darkPanelColor : Colors.white,
                    icon: RotatedBox(
                      quarterTurns: _toolbarOnLeft ? -1 : 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
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
                                  : _textColor,
                            ),
                            Icon(
                              Icons.arrow_drop_down_rounded,
                              size: 16,
                              color: _activeShapeTool != null
                                  ? const Color(0xFF6366F1)
                                  : _textColor,
                            ),
                          ],
                        ),
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
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 2,
                                    ),
                                    padding: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? const Color(
                                              0xFF6366F1,
                                            ).withOpacity(0.25)
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
                                          : _textColor,
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
                    icon: RotatedBox(
                      quarterTurns: _toolbarOnLeft ? -1 : 0,
                      child: Row(
                        children: [
                          Icon(
                            _bgMode == CanvasBgMode.grid
                                ? Icons.grid_on_rounded
                                : (_bgMode == CanvasBgMode.ruled
                                      ? Icons.notes_rounded
                                      : Icons.crop_portrait_rounded),
                            size: 18,
                            color: _textColor,
                          ),
                        ],
                      ),
                    ),
                    color: isDark ? _darkPanelColor : Colors.white,
                    onSelected: (m) => setState(() => _bgMode = m),
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: CanvasBgMode.grid,
                        child: Text(
                          '📐 Math Grid',
                          style: TextStyle(color: _textColor),
                        ),
                      ),
                      PopupMenuItem(
                        value: CanvasBgMode.ruled,
                        child: Text(
                          '📝 Ruled Lines',
                          style: TextStyle(color: _textColor),
                        ),
                      ),
                      PopupMenuItem(
                        value: CanvasBgMode.blank,
                        child: Text(
                          '📄 Blank Canvas',
                          style: TextStyle(color: _textColor),
                        ),
                      ),
                    ],
                  ),

                  // Theme Mode Toggle
                  PopupMenuButton<MathPadTheme>(
                    tooltip: 'App Theme',
                    icon: RotatedBox(
                      quarterTurns: _toolbarOnLeft ? -1 : 0,
                      child: Row(
                        children: [
                          Icon(
                            _themeMode == MathPadTheme.cosmos
                                ? Icons.auto_awesome_rounded
                                : (_themeMode == MathPadTheme.aswadLail
                                      ? Icons.nights_stay_rounded
                                      : (_themeMode == MathPadTheme.dark
                                            ? Icons.dark_mode_rounded
                                            : Icons.light_mode_rounded)),
                            size: 18,
                            color: _textColor,
                          ),
                        ],
                      ),
                    ),
                    color: isDark ? _darkPanelColor : Colors.white,
                    onSelected: (m) async {
                      setState(() {
                        _themeMode = m;
                      });
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('mathpad_default_theme', m.name);
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: MathPadTheme.light,
                        child: Text(
                          '☀️ Light Mode',
                          style: TextStyle(color: _textColor),
                        ),
                      ),
                      PopupMenuItem(
                        value: MathPadTheme.dark,
                        child: Text(
                          '🌙 Dark Mode',
                          style: TextStyle(color: _textColor),
                        ),
                      ),
                      PopupMenuItem(
                        value: MathPadTheme.cosmos,
                        child: Text(
                          '🌌 Jyamiti Cosmos (#0F2B52)',
                          style: TextStyle(color: _textColor),
                        ),
                      ),
                      PopupMenuItem(
                        value: MathPadTheme.aswadLail,
                        child: Text(
                          '⚫ Aswad Lail (#000000)',
                          style: TextStyle(color: _textColor),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(width: 10),

                  // Zoom Controls moved to bottom overlay

                  // Full Screen Toggle Button
                  if (widget.onToggleFullScreen != null) ...[
                    animated(
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
                    ),
                    const SizedBox(width: 4),
                  ],

                  // Undo / Redo / Clear
                  animated(
                    _buildIconButton(
                      icon: Icons.undo_rounded,
                      tooltip: 'Undo',
                      isDisabled: _lines.isEmpty,
                      onTap: _undo,
                    ),
                  ),
                  animated(
                    _buildIconButton(
                      icon: Icons.redo_rounded,
                      tooltip: 'Redo',
                      isDisabled: _undoHistory.isEmpty,
                      onTap: _redo,
                    ),
                  ),
                  animated(
                    _buildIconButton(
                      icon: Icons.delete_outline_rounded,
                      tooltip: 'Clear Canvas',
                      color: Colors.redAccent,
                      onTap: _clearCanvas,
                    ),
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
                            color: const Color(
                              0xFF10B981,
                            ).withValues(alpha: 0.15),
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

                  if (widget.onSaveRequested != null) ...[
                    const SizedBox(width: 6),
                    Tooltip(
                      message: 'Save Page',
                      child: InkWell(
                        onTap: _savePage,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF10B981,
                            ).withValues(alpha: 0.15),
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
                            color: const Color(
                              0xFF0EA5E9,
                            ).withValues(alpha: 0.15),
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

                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                      Icons.view_sidebar_rounded,
                      size: 20,
                      color: _textColor,
                    ),
                    onPressed: () =>
                        setState(() => _toolbarOnLeft = !_toolbarOnLeft),
                    tooltip: _toolbarOnLeft
                        ? 'Move Toolbar to Top'
                        : 'Move Toolbar to Left Side',
                  ),

                  if (!kIsWeb &&
                      MathPadRecordingService.isSupportedPlatform) ...[
                    // Real-time background segment sealing strategy (see
                    // `SegmentSealMode`) -- locked while a recording is
                    // actually in progress, since changing it mid-recording
                    // would apply inconsistently to what's already been
                    // captured vs. what's still to come.
                    PopupMenuButton<SegmentSealMode>(
                      tooltip: 'Recording: background encoding strategy',
                      enabled: _recordingState == MathPadRecordingState.idle,
                      icon: Icon(
                        Icons.settings_suggest_rounded,
                        size: 20,
                        color: _recordingState == MathPadRecordingState.idle
                            ? _textColor
                            : _textColor60,
                      ),
                      color: isDark ? _darkPanelColor : Colors.white,
                      onSelected: (mode) {
                        setState(() {
                          unawaited(_recordingService.setSegmentSealMode(mode));
                        });
                      },
                      itemBuilder: (ctx) => [
                        _segmentSealModeMenuItem(
                          SegmentSealMode.hybrid,
                          'Hybrid (Recommended)',
                          'Seals on a pause, or every 20s -- whichever comes first',
                        ),
                        _segmentSealModeMenuItem(
                          SegmentSealMode.idleOnly,
                          'Idle only',
                          'Seals only during a natural pause (tutor talking, not drawing)',
                        ),
                        _segmentSealModeMenuItem(
                          SegmentSealMode.fixedInterval,
                          'Fixed interval',
                          'Seals every 20s, regardless of activity',
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    // Capture vs. final-video frame rate (see
                    // `RecordingFrameRateMode`) -- also locked while a
                    // recording is in progress, same reasoning as above.
                    PopupMenuButton<RecordingFrameRateMode>(
                      tooltip: 'Recording: frame rate',
                      enabled: _recordingState == MathPadRecordingState.idle,
                      icon: Icon(
                        Icons.video_settings_rounded,
                        size: 20,
                        color: _recordingState == MathPadRecordingState.idle
                            ? _textColor
                            : _textColor60,
                      ),
                      color: isDark ? _darkPanelColor : Colors.white,
                      onSelected: (mode) {
                        setState(() {
                          unawaited(_recordingService.setFrameRateMode(mode));
                        });
                      },
                      itemBuilder: (ctx) => [
                        _frameRateModeMenuItem(
                          RecordingFrameRateMode.balanced,
                          'Balanced (Recommended)',
                          '60fps sampling, 30fps video -- smaller files, same '
                              'smoothness as 60/60',
                        ),
                        _frameRateModeMenuItem(
                          RecordingFrameRateMode.smooth60,
                          '60 fps',
                          'Smoothest motion, largest files -- full 60fps sampling and video',
                        ),
                        _frameRateModeMenuItem(
                          RecordingFrameRateMode.compact30,
                          '30 fps',
                          'Smallest files -- 30fps sampling and video, slightly '
                              'coarser on fast strokes',
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    if (_recordingState == MathPadRecordingState.recording)
                      IconButton(
                        icon: const Icon(
                          Icons.stop_circle_rounded,
                          size: 20,
                          color: Colors.redAccent,
                        ),
                        onPressed: _stopRecording,
                        tooltip: 'Stop Recording',
                      )
                    else if (_recordingState == MathPadRecordingState.encoding)
                      IconButton(
                        icon: Icon(
                          Icons.fiber_manual_record_rounded,
                          size: 20,
                          color: _textColor60,
                        ),
                        onPressed: null,
                        tooltip: 'Encoding…',
                      )
                    else
                      PopupMenuButton<bool>(
                        tooltip: 'Start Recording',
                        icon: Icon(
                          Icons.fiber_manual_record_rounded,
                          size: 20,
                          color: _textColor,
                        ),
                        color: isDark ? _darkPanelColor : Colors.white,
                        onSelected: (withCamera) =>
                            _startRecording(includeCamera: withCamera),
                        itemBuilder: (ctx) => [
                          _recordingOptionMenuItem(
                            value: false,
                            icon: Icons.videocam_off_rounded,
                            iconColor: _textColor,
                            label: 'Without Camera',
                            description: 'Record canvas & microphone audio only',
                          ),
                          _recordingOptionMenuItem(
                            value: true,
                            icon: Icons.videocam_rounded,
                            iconColor: const Color(0xFF6366F1),
                            label: 'With Camera',
                            description: 'Record canvas, audio & webcam overlay PIP',
                          ),
                        ],
                      ),
                  ],

                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                      _isFullScreenMode
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                      size: 20,
                      color: _textColor,
                    ),
                    onPressed: () => setState(() {
                      _isFullScreenMode = !_isFullScreenMode;
                      _toolbarRevealedInFullScreen = false;
                      widget.onCanvasOnlyModeChanged?.call(_isFullScreenMode);
                    }),
                    tooltip: _isFullScreenMode
                        ? 'Exit Full Screen'
                        : 'Full Screen (canvas only)',
                  ),

                  if (widget.onClose != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: _textColor,
                      ),
                      onPressed: _handleCloseTap,
                      tooltip: 'Close Writing Screen',
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (widget.trailingToolbarAction != null) ...[
            const SizedBox(width: 12),
            Container(
              width: 1,
              height: 32,
              color: isDark ? Colors.white24 : Colors.black12,
            ),
            const SizedBox(width: 12),
            RotatedBox(
              quarterTurns: _toolbarOnLeft ? -1 : 0,
              child: widget.trailingToolbarAction!,
            ),
          ],
        ],
      ),
    );
  }

  PopupMenuItem<bool> _recordingOptionMenuItem({
    required bool value,
    required IconData icon,
    required Color iconColor,
    required String label,
    required String description,
  }) {
    return PopupMenuItem<bool>(
      value: value,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: _textColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(color: _textColor60, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One row in the recording-segment-sealing-strategy popup (see
  /// `SegmentSealMode`'s own doc comment for what each option actually
  /// does) -- a label, a one-line plain-language description, and a radio
  /// dot showing whether it's the currently active choice.
  PopupMenuItem<SegmentSealMode> _segmentSealModeMenuItem(
    SegmentSealMode mode,
    String label,
    String description,
  ) {
    final bool selected = _recordingService.segmentSealMode == mode;
    return PopupMenuItem<SegmentSealMode>(
      value: mode,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            selected
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 18,
            color: selected ? const Color(0xFF6366F1) : _textColor60,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: _textColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(color: _textColor60, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One row in the recording-frame-rate popup (see
  /// `RecordingFrameRateMode`'s own doc comment for the full benefit/cost
  /// breakdown of each option) -- same label/description/radio-dot layout
  /// as `_segmentSealModeMenuItem` above.
  PopupMenuItem<RecordingFrameRateMode> _frameRateModeMenuItem(
    RecordingFrameRateMode mode,
    String label,
    String description,
  ) {
    final bool selected = _recordingService.frameRateMode == mode;
    return PopupMenuItem<RecordingFrameRateMode>(
      value: mode,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            selected
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 18,
            color: selected ? const Color(0xFF6366F1) : _textColor60,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: _textColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(color: _textColor60, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    IconData? icon,
    Widget Function(Color color)? customIconBuilder,
    required String tooltip,
    required VoidCallback onTap,
    bool isSelected = false,
    bool isDisabled = false,
    Color? color,
  }) {
    final Color resolvedColor = isDisabled
        ? Colors.grey.withOpacity(0.3)
        : (isSelected ? const Color(0xFF6366F1) : (color ?? _textColor));
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
          child: RotatedBox(
            quarterTurns: _toolbarOnLeft ? -1 : 0,
            child: customIconBuilder != null
                ? customIconBuilder(resolvedColor)
                : Icon(icon, size: 18, color: resolvedColor),
          ),
        ),
      ),
    );
  }

  Future<bool> _onWillPop() async {
    if (_recordingState == MathPadRecordingState.recording) {
      final bool? confirmClose = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final isDark = _isDarkTheme;
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            backgroundColor: isDark ? _darkPanelColor : Colors.white,
            title: Text(
              'Recording in Progress',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              'You have an active recording. If you exit now, the recording will be discarded. Are you sure you want to exit?',
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: context.textColor60),
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Exit Anyway'),
              ),
            ],
          );
        },
      );

      if (confirmClose == true) {
        final recordingService = context.read<MathPadRecordingService>();
        await recordingService.cancel();
        return true;
      }
      return false;
    }
    return true;
  }

  /// A small hand-drawn protractor glyph (semicircle body + a few degree
  /// ticks) for the "Add Protractor" toolbar button -- no stock Material
  /// icon actually looks like a protractor, so this mirrors the real
  /// `ProtractorWidget`'s shape/orientation at icon scale instead of using
  /// an unrelated placeholder icon.
  Widget _buildProtractorIcon(Color color) {
    return SizedBox(
      width: 18,
      height: 18,
      child: CustomPaint(painter: _ProtractorIconPainter(color: color)),
    );
  }

  /// Hands the full current canvas content to `widget.onSaveRequested`
  /// (the Math Pad Library's page editor, when opened from there).
  Future<void> _savePage() async {
    if (widget.onSaveRequested == null) return;
    await widget.onSaveRequested!(
      lines: _lines,
      instruments: _instruments,
      textLabels: _textLabels,
      fixedAngleLabels: _fixedAngleLabels,
      bgMode: _bgMode,
      themeMode:
          _themeMode ??
          (context.isDark ? MathPadTheme.dark : MathPadTheme.light),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Page saved'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    }
  }

  /// The ✕ button's handler. When this pad was opened with a save hook
  /// (i.e. from the Math Pad Library), everything is already being
  /// autosaved continuously -- so closing just does one last silent save
  /// (to catch anything since the last autosave tick) and leaves, with no
  /// interrupting prompt. Otherwise falls straight through to
  /// `widget.onClose` unchanged, so every other/older caller's behavior is
  /// exactly as before.
  Future<void> _handleCloseTap() async {
    if (!await _onWillPop()) return;

    if (widget.onSaveRequested != null) {
      await widget.onSaveRequested!(
        lines: _lines,
        instruments: _instruments,
        textLabels: _textLabels,
        fixedAngleLabels: _fixedAngleLabels,
        bgMode: _bgMode,
        themeMode:
            _themeMode ??
            (context.isDark ? MathPadTheme.dark : MathPadTheme.light),
      );
    }
    widget.onClose?.call();
  }

  Future<void> _saveNote() async {
    final titleController = TextEditingController(text: widget.noteTitle ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = _isDarkTheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: isDark ? _darkPanelColor : Colors.white,
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
          .map(
            (p) => {
              'dx': p.offset.dx,
              'dy': p.offset.dy,
              if (p.pressure != null) 'pr': p.pressure,
            },
          )
          .toList(),
      'color': line.color.value,
      'strokeWidth': line.strokeWidth,
      'isEraser': line.isEraser,
      'isShape': line.isShape,
      'isPencil': line.isPencil,
    };
  }
}

/// The signed angular delta from [from] to [to] (both in radians, any
/// range), taking the shortest path and always in (-pi, pi] -- used to
/// advance a continuously-unwrapped angle from repeated wrapped
/// `Offset.direction` samples (e.g. the Circle/Arc Tool's sweep) without a
/// discontinuity when the raw angle crosses the -pi/pi boundary.
double _shortestAngleDelta(double from, double to) {
  double delta = (to - from) % (2 * pi);
  if (delta > pi) delta -= 2 * pi;
  if (delta < -pi) delta += 2 * pi;
  return delta;
}

// ── Top-Level Helper Utilities for High Performance Curve Smoothing ─────────────

/// How many new raw points accumulate before `_buildLivePath` re-runs full
/// Chaikin smoothing over the live stroke-so-far, rather than reusing the
/// last smoothing pass plus a cheap straight tail segment. See the comment
/// at its use site for why this exists.
const int _kLiveSmoothRebuildEvery = 6;

/// How many new raw points accumulate, while a single freehand/eraser
/// stroke is still being drawn, before its already-drawn portion gets
/// folded into Layer 2a -- its own small `RepaintBoundary`-cached
/// snapshot, exactly like the ones committed strokes get via
/// `_bakedChunks`. Without this, `_MathsPadActiveOverlayPainter` had to
/// rebuild AND re-rasterize a path covering the ENTIRE stroke-so-far on
/// every single drawing frame -- cheap for a short stroke, but for one
/// long continuous line (e.g. writing a full sentence without lifting
/// the pen, thousands of points before it's committed) that cost grows
/// with the stroke itself, which is exactly why drawing got progressively
/// slower the longer a single stroke ran. Baking the stable prefix into a
/// real GPU-cached layer bounds the live per-frame work to roughly the
/// last `_kLiveBakeEvery` points, regardless of how long the whole stroke
/// ends up being -- same idea as `_kBakeThreshold`, just applied within
/// one still-in-progress stroke instead of across many finished ones.
const int _kLiveBakeEvery = 40;

/// Builds a (optionally Chaikin-smoothed) path for just `line.points[start,
/// end)`, instead of the whole stroke -- the range-based twin of
/// `_buildLivePath`, used by Layer 2a (the baked-so-far snapshot, a large
/// but infrequently-rebuilt range) and Layer 2's live tail (a small range
/// rebuilt every frame). Smoothing a sub-range independently of its
/// neighbours can leave an imperceptible seam where the two meet -- points
/// are dense enough (see the `>= 1.2` spacing check at the call site) that
/// this isn't visible in practice, matching the same trade-off
/// `_kLiveSmoothRebuildEvery`'s cached-tail already makes.
Path _buildLivePathRange(MathsPadLine line, int start, int end) {
  final path = Path();
  final int s = start.clamp(0, line.points.length);
  final int e = end.clamp(0, line.points.length);
  if (e - s <= 0) return path;

  path.moveTo(line.points[s].offset.dx, line.points[s].offset.dy);
  if (e - s == 1) return path;
  if (e - s == 2) {
    path.lineTo(line.points[s + 1].offset.dx, line.points[s + 1].offset.dy);
    return path;
  }

  if (line.isShape) {
    for (int i = s + 1; i < e; i++) {
      path.lineTo(line.points[i].offset.dx, line.points[i].offset.dy);
    }
    return path;
  }

  final List<Offset> rawOffsets = line.points
      .sublist(s, e)
      .map((p) => p.offset)
      .toList();
  final List<Offset> smoothPts = _chaikinSmooth(rawOffsets, iterations: 2);
  for (int i = 1; i < smoothPts.length - 1; i++) {
    final pPrev = smoothPts[i];
    final pNext = smoothPts[i + 1];
    final midX = (pPrev.dx + pNext.dx) / 2;
    final midY = (pPrev.dy + pNext.dy) / 2;
    path.quadraticBezierTo(pPrev.dx, pPrev.dy, midX, midY);
  }
  path.lineTo(line.points[e - 1].offset.dx, line.points[e - 1].offset.dy);
  return path;
}

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

// Builds a pressure-sensitive stroke outline for the Pencil tool using
// perfect_freehand, returning a closed fillable polygon path -- completely
// separate from the Chaikin/quadratic-bezier centerline path Pen strokes
// use above. Uses each point's real stylus pressure when available;
// otherwise simulates pressure from stroke velocity (perfect_freehand's
// signature tapered look), matching the Pencil tool on the whiteboard
// (`writing_pad_widget.dart`'s `_buildPencilOutlinePath`).
Path _buildPencilOutlinePath(MathsPadLine line, {bool isComplete = true}) {
  final path = Path();
  if (line.points.isEmpty) return path;

  final bool hasRealPressure = line.points.any((p) => p.pressure != null);
  final List<PointVector> inputPoints = line.points
      .map((p) => PointVector(p.offset.dx, p.offset.dy, p.pressure))
      .toList();

  final List<Offset> outline = getStroke(
    inputPoints,
    options: StrokeOptions(
      size: line.strokeWidth,
      thinning: 0.5,
      smoothing: 0.7,
      streamline: 0.65,
      simulatePressure: !hasRealPressure,
      isComplete: isComplete,
    ),
  );

  if (outline.isEmpty) return path;
  if (outline.length < 3) {
    path.moveTo(outline[0].dx, outline[0].dy);
    for (int i = 1; i < outline.length; i++) {
      path.lineTo(outline[i].dx, outline[i].dy);
    }
    path.close();
    return path;
  }

  // Smooth the outline polygon with quadratic Bézier curves so curves and
  // corners render as polished arcs instead of jagged straight segments.
  path.moveTo(outline[0].dx, outline[0].dy);
  for (int i = 1; i < outline.length - 1; i++) {
    final midX = (outline[i].dx + outline[i + 1].dx) / 2;
    final midY = (outline[i].dy + outline[i + 1].dy) / 2;
    path.quadraticBezierTo(outline[i].dx, outline[i].dy, midX, midY);
  }
  // Final segment back to the closing point
  path.quadraticBezierTo(
    outline[outline.length - 2].dx,
    outline[outline.length - 2].dy,
    outline.last.dx,
    outline.last.dy,
  );
  path.close();
  return path;
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

  if (line.isPencil) {
    line.cachedPath = _buildPencilOutlinePath(line, isComplete: true);
  } else if (line.isShape || line.points.length <= 2) {
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

// ── Background grid/ruled paper pattern -- its own screen-space painter,
// separate from the ink-content painter below. It still needs live pan/
// scale every frame to know which grid lines are actually on screen, but
// that's cheap (a few dozen straight `drawLine` calls, no anti-aliased
// stroke paths/shaders/saveLayer) unlike real ink content, so it can keep
// tracking a live pan/zoom gesture at full frame rate for free while the
// (potentially large) finished-strokes layers below sit behind a single
// ancestor `Transform` instead (see `build`'s Layer 1a/1b) and don't
// repaint at all during panning.
class _MathsPadGridBackgroundPainter extends CustomPainter {
  final CanvasBgMode bgMode;
  final bool isDark;
  final Offset panOffset;
  final double scale;

  _MathsPadGridBackgroundPainter({
    required this.bgMode,
    required this.isDark,
    required this.panOffset,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (bgMode == CanvasBgMode.blank) return;
    final double startX = ((-panOffset.dx) / scale);
    final double endX = ((size.width - panOffset.dx) / scale);
    final double startY = ((-panOffset.dy) / scale);
    final double endY = ((size.height - panOffset.dy) / scale);

    canvas.save();
    canvas.translate(panOffset.dx, panOffset.dy);
    canvas.scale(scale);
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
        canvas.drawLine(Offset(x, gridStartY), Offset(x, gridEndY), gridPaint);
      }
      for (double y = gridStartY; y <= gridEndY; y += step) {
        canvas.drawLine(Offset(gridStartX, y), Offset(gridEndX, y), gridPaint);
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
        canvas.drawLine(Offset(gridStartX, y), Offset(gridEndX, y), gridPaint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MathsPadGridBackgroundPainter oldDelegate) {
    return oldDelegate.panOffset != panOffset ||
        oldDelegate.scale != scale ||
        oldDelegate.bgMode != bgMode ||
        oldDelegate.isDark != isDark;
  }
}

// ── Layer 1: Finished Strokes Painter ───────────────────────────────────────
class _MathsPadFinishedStrokesPainter extends CustomPainter {
  final List<MathsPadLine> lines;
  // True for the "recent" layer (always) and for a baked chunk whose
  // precomputed bounds currently overlap the viewport -- an off-screen
  // chunk still gets a `CustomPaint` (see `build`'s Layer 1a: EVERY chunk
  // stays permanently mounted, on purpose, to avoid the GPU layer
  // create/destroy churn a widget-level mount/unmount version of this
  // caused -- confirmed by the user as the cause of a delayed
  // "everything freezes for a stretch" stall after zooming), it just
  // skips its own drawing work below when this is false, which is the
  // actual expensive part (scaling forces Skia to recompute anti-aliased
  // stroke edges, unlike panning which can reuse what's already there).
  final bool isVisible;

  /// Only the lines from [lines] that are ALSO currently selected --
  /// computed once here from the full page-wide selection passed in as
  /// [allSelectedLines], rather than storing that whole set as-is, so
  /// `shouldRepaint` below can cheaply and CORRECTLY detect a selection
  /// change that actually matters to THIS chunk specifically (via
  /// `setEquals`), regardless of what else changed in the selection
  /// elsewhere on the page. A single "does this chunk contain ANY
  /// selected line" bool would not be precise enough: e.g. deselecting
  /// one line in this chunk while selecting a DIFFERENT line also in
  /// this chunk, in the same update, would leave such a bool unchanged
  /// even though this chunk's rendering needs to skip a different line
  /// now. Skipped here entirely -- not drawn by this layer at all -- a
  /// selected line's actual content is instead drawn live by
  /// `_MathsPadActiveOverlayPainter` (Layer 2), on top of everything
  /// else, for as long as it stays selected; see that class's
  /// `_drawSelectedLinesOnTop`.
  final Set<MathsPadLine> selectedInThisLayer;

  _MathsPadFinishedStrokesPainter({
    required this.lines,
    this.isVisible = true,
    Set<MathsPadLine> allSelectedLines = const {},
  }) : selectedInThisLayer = (lines.isEmpty || allSelectedLines.isEmpty)
           ? const {}
           : lines.where(allSelectedLines.contains).toSet();

  @override
  void paint(Canvas canvas, Size size) {
    if (!isVisible) return;
    // No camera transform here -- an ancestor `Transform` (see `build`'s
    // Layer 1a/1b) positions this whole layer in world space instead, so
    // panning/zooming is a GPU compositor operation that reuses this
    // layer's already-rasterized content instead of re-running these
    // paint calls on every pan/zoom frame. `lines` is always a small,
    // bounded list (one sealed chunk, or the capped "recent" tail -- see
    // `_kBakeThreshold`), so drawing it unconditionally (no viewport
    // culling) is cheap; culling existed only to bound cost against a
    // page's ENTIRE history, which chunking already does structurally.

    // Pass 1: Fill Tool underlays -- always bottom, regardless of when
    // they were actually created (`_lines` itself stays strictly
    // chronological -- `_undo()` depends on `removeLast()` picking
    // whatever was really added last -- so this reordering is purely
    // visual). Drawn OUTSIDE the ink `saveLayer`(s) below for the same
    // reason pasted images are (see Pass 2): an eraser line's
    // `BlendMode.clear` clears whatever else shares its `saveLayer`
    // scope regardless of draw order, so an image can only be guaranteed
    // immune to the Eraser tool by never sharing that scope at all.
    for (final line in lines) {
      if (line.fillImage == null ||
          line.fillWorldBounds == null ||
          line.isPastedImage ||
          selectedInThisLayer.contains(line)) {
        continue;
      }
      _paintFillImage(canvas, line);
    }

    // Pass 2: ink and pasted images, interleaved in TRUE chronological
    // order (unlike a Fill Tool image, always forced to the bottom in
    // Pass 1) -- a pasted image renders above whatever came before it
    // and below whatever came after, images or ink alike, matching any
    // ordinary note-taking app: paste a photo, annotate over it, and
    // that annotation stays on top; paste a second photo on top of the
    // first afterward, and IT stays on top. Grouped into contiguous
    // "runs" of ink between pasted images (rather than one flat loop
    // like Pass 1/the old Pass 3) so an eraser line's `saveLayer`/
    // `BlendMode.clear` scope -- still needed per run, exactly as
    // before -- can never end up including a pasted image no matter how
    // the two interleave in `lines`: an image is only ever guaranteed
    // immune to the Eraser tool by never sharing that scope at all.
    int i = 0;
    while (i < lines.length) {
      final MathsPadLine line = lines[i];
      if (selectedInThisLayer.contains(line)) {
        i++;
        continue;
      }
      if (line.fillImage != null && line.fillWorldBounds != null) {
        if (line.isPastedImage) {
          _paintFillImage(canvas, line);
        }
        // A Fill Tool image was already drawn back in Pass 1 -- nothing
        // to do for it here.
        i++;
        continue;
      }

      // Collect a contiguous run of ink lines, up to the next image or
      // selected line -- guaranteed non-empty: `lines[i]` itself is
      // neither (both cases above already `continue`d), so this inner
      // loop always advances `i` at least once.
      final int start = i;
      while (i < lines.length) {
        final MathsPadLine l = lines[i];
        if (l.fillImage != null || selectedInThisLayer.contains(l)) break;
        i++;
      }
      final List<MathsPadLine> inkRun = lines.sublist(start, i);
      for (final l in inkRun) {
        _paintInkLine(canvas, l);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MathsPadFinishedStrokesPainter oldDelegate) {
    // A sealed baked chunk passes the EXACT SAME `List<MathsPadLine>`
    // instance in on every rebuild (see `_bakedChunks`) -- `identical()`
    // catches that cheaply (no need to diff contents) and lets the
    // compositor keep reusing that chunk's already-rasterized layer
    // instead of re-running every stroke's paint calls each time a later
    // chunk/rebuild touches an unrelated sibling. The "recent" sub-layer's
    // list is a fresh `sublist()` every time by design (it's the one
    // that's actually supposed to redraw on every new commit), so this
    // still repaints it as before. No `panOffset`/`scale` fields to
    // compare -- an ancestor `Transform` handles positioning now (see
    // `build`'s Layer 1a/1b), so this painter is never re-run just because
    // the user panned or zoomed. `isVisible` DOES need comparing: a chunk
    // whose viewport-overlap status flips between frames genuinely needs
    // to actually draw (or actually stop drawing) its content -- but a
    // chunk that STAYS visible (or stays invisible) across consecutive
    // frames, with the same `lines`, still correctly skips repainting.
    // `selectedInThisLayer` (via `setEquals`, see its own doc comment for
    // why a plain identity/bool check isn't precise enough) covers a
    // selection change that adds/removes one of THIS chunk's own lines --
    // including throughout an active move/rotate/resize drag, which no
    // longer touches `lines`/`isVisible` at all (see `_onScaleUpdate`),
    // so without this the chunk would never repaint to actually hide a
    // freshly-selected line.
    return !identical(oldDelegate.lines, lines) ||
        oldDelegate.isVisible != isVisible ||
        !setEquals(oldDelegate.selectedInThisLayer, selectedInThisLayer);
  }
}

/// Draws a single line's actual image content at its current position --
/// shared by `_MathsPadFinishedStrokesPainter` (normal committed
/// rendering, both Fill Tool and pasted images) and
/// `_MathsPadActiveOverlayPainter` (drawing a SELECTED image's content a
/// second time, live, on top of everything else -- see
/// `_drawSelectedLinesOnTop`).
void _paintFillImage(Canvas canvas, MathsPadLine line) {
  final bool rotated = line.rotation != 0;
  if (rotated) {
    canvas.save();
    final Offset center = line.fillWorldBounds!.center;
    canvas.translate(center.dx, center.dy);
    canvas.rotate(line.rotation);
    canvas.translate(-center.dx, -center.dy);
  }
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
  if (rotated) {
    canvas.restore();
  }
}

/// Draws a single line's actual ink content (a stroke or eraser path) at
/// its current position -- shared by `_MathsPadFinishedStrokesPainter`
/// (normal committed rendering) and `_MathsPadActiveOverlayPainter`
/// (drawing a SELECTED stroke's content a second time, live, on top of
/// everything else -- see `_drawSelectedLinesOnTop`). Callers are
/// responsible for skipping image lines themselves (this never checks
/// `fillImage`) and for any `saveLayer` an eraser line needs.
void _paintInkLine(Canvas canvas, MathsPadLine line) {
  if (line.points.isEmpty) return;

  final paint = Paint()
    ..isAntiAlias = true
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;

  if (line.isMagic && line.points.isNotEmpty) {
    paint.shader = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFFFF7A00),
        Color(0xFFFF2E9A),
        Color(0xFF00E5FF),
        Color(0xFF39FF14),
        Color(0xFFFF7A00),
      ],
      tileMode: TileMode.repeated,
    ).createShader(const Rect.fromLTWH(0, 0, 100, 100));
  } else {
    paint.shader = null;
    paint.color = line.color;
    if (line.isPencil) {
      // Pencil strokes are a filled perfect_freehand outline polygon, not
      // a stroked centerline -- fill it instead.
      paint.style = PaintingStyle.fill;
    }
  }
  paint.strokeWidth = line.strokeWidth;

  if (line.points.length == 1) {
    paint.style = PaintingStyle.fill;
    canvas.drawCircle(line.points.first.offset, paint.strokeWidth / 2, paint);
  } else {
    if (line.cachedPath == null) {
      _buildAndCachePath(line);
    }

    if (!line.isEraser && !line.isPencil) {
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

// ── Layer 2a: Baked-So-Far Snapshot of the In-Progress Stroke ──────────────────
/// A GPU-cached snapshot (via the `RepaintBoundary` this is wrapped in --
/// see `build()`) of everything already drawn for the CURRENTLY
/// in-progress freehand/eraser stroke, up to `bakedPointCount` raw points.
/// Exactly the same idea as `_bakedChunks` for committed strokes, applied
/// within one still-in-progress stroke: `shouldRepaint` only returns true
/// when `bakedPointCount` actually changes (every `_kLiveBakeEvery` new
/// points), so this only pays real rasterization cost once per bake, not
/// on every single drawing frame. The rest of the still-changing tail is
/// drawn separately, live, by `_MathsPadActiveOverlayPainter` below.
class _MathsPadLiveStrokeBakedPainter extends CustomPainter {
  final MathsPadLine? line;
  final int bakedPointCount;

  _MathsPadLiveStrokeBakedPainter({
    required this.line,
    required this.bakedPointCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final MathsPadLine? l = line;
    if (l == null || bakedPointCount < 2) return;

    final Path path = _buildLivePathRange(l, 0, bakedPointCount);
    final paint = Paint()
      ..isAntiAlias = true
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (l.isEraser) {
      // Draw the eraser path as a translucent red "highlighter" trail so the
      // user can see exactly what they're erasing before they lift their finger.
      paint.color = const Color(0xFFF43F5E).withValues(alpha: 0.35); // Rose-500
      paint.strokeWidth = l.strokeWidth * 3.5;
      canvas.drawPath(path, paint);
      return;
    }

    if (l.isMagic) {
      paint.shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFF7A00),
          Color(0xFFFF2E9A),
          Color(0xFF00E5FF),
          Color(0xFF39FF14),
          Color(0xFFFF7A00),
        ],
        tileMode: TileMode.repeated,
      ).createShader(const Rect.fromLTWH(0, 0, 100, 100));
    } else {
      paint.shader = null;
      paint.color = l.color;
    }
    paint.strokeWidth = l.strokeWidth;

    final softUnderPaint = Paint()
      ..isAntiAlias = true
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..color = l.color.withValues(alpha: 0.12)
      ..strokeWidth = l.strokeWidth * 1.35;
    canvas.drawPath(path, softUnderPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MathsPadLiveStrokeBakedPainter oldDelegate) {
    return !identical(oldDelegate.line, line) ||
        oldDelegate.bakedPointCount != bakedPointCount;
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
  final List<_LaserTrailPoint> laserTrail;
  final double selectionGlowPhase;
  final Offset? eraserCursorPos;
  final double eraserCursorRadius;
  final bool isRecording;

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
    this.laserTrail = const [],
    this.selectionGlowPhase = 0.0,
    this.eraserCursorPos,
    this.eraserCursorRadius = 20.0,
    this.isRecording = false,
  });

  /// Mirrors `_MathsPadWidgetState._selectedImageRotation` -- when exactly
  /// one image line is selected, the selection box/handles are drawn
  /// rotated to match it (see `_drawSelectionOverlay`) instead of staying
  /// axis-aligned while only the image itself visually spins.
  double get _selectedImageRotation {
    if (selectedLines.length == 1) {
      final line = selectedLines.first;
      if (line.fillImage != null) return line.rotation;
    }
    return 0;
  }

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
    // No camera transform here -- an ancestor `Transform` (see `build`,
    // merged into the SAME shared Transform as Layer 1a/1b) positions this
    // whole layer in world space instead, same as the finished-strokes
    // painter. This used to apply `canvas.translate(panOffset)`/`canvas.
    // scale(scale)` directly here, which is EXACTLY what the
    // finished-strokes painter did too before today's pan/zoom performance
    // work moved it to the ancestor-`Transform` approach -- leaving this
    // painter on the old CPU-canvas-transform mechanism while the
    // committed-stroke layers moved to a GPU `TransformLayer` introduced a
    // small but consistent precision/rounding mismatch between the two,
    // which showed up as every single stroke visibly popping to a very
    // slightly different position the instant it was committed (this
    // painter draws the live in-progress stroke; the finished layers draw
    // it from the moment after). `panOffset` is no longer used for a
    // transform, only `scale` -- still needed throughout this painter's
    // OTHER code below to size handles/labels/glow radii as a constant
    // SCREEN size regardless of zoom (dividing by `scale`), unrelated to
    // which mechanism applies the top-level transform.
    canvas.save();
    try {
      // 1. Draw Active Stroke Live Path
      // 1. Draw Active Stroke Live Path
      if (currentLine != null && currentLine!.points.isNotEmpty) {
        final line = currentLine!;

        if (line.isPencil) {
          // Pencil: pressure-sensitive perfect_freehand fill, recomputed
          // fresh every frame (never baked, see `_onScaleUpdate`) --
          // completely separate from the Pen/Eraser/Magic Pen stroke path
          // in the `else` branch below, which stays untouched.
          final fillPaint = Paint()
            ..isAntiAlias = true
            ..style = PaintingStyle.fill
            ..color = line.color;
          if (line.points.length == 1) {
            canvas.drawCircle(
              line.points.first.offset,
              line.strokeWidth / 2,
              fillPaint,
            );
          } else {
            final Path livePath = _buildPencilOutlinePath(
              line,
              isComplete: false,
            );
            canvas.drawPath(livePath, fillPaint);
          }
        } else {
          final paint = Paint()
            ..isAntiAlias = true
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke;

          if (line.isEraser) {
            // Draw the eraser path as a translucent red "highlighter" trail so the
            // user can see exactly what they're erasing before they lift their finger.
            paint.color = const Color(
              0xFFF43F5E,
            ).withValues(alpha: 0.35); // Rose-500
            paint.strokeWidth = line.strokeWidth * 3.5;
          } else if (line.isMagic && line.points.isNotEmpty) {
            paint.shader = const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFF7A00),
                Color(0xFFFF2E9A),
                Color(0xFF00E5FF),
                Color(0xFF39FF14),
                Color(0xFFFF7A00),
              ],
              tileMode: TileMode.repeated,
            ).createShader(const Rect.fromLTWH(0, 0, 100, 100));
          } else {
            paint.shader = null;
            paint.color = line.color;
          }

          if (!line.isEraser) {
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
            // Only draw what Layer 2a's cached "stroke-so-far" snapshot
            // doesn't already cover -- a few points of overlap for
            // smoothing continuity at the seam -- instead of the whole
            // line every frame. See `_kLiveBakeEvery`'s doc comment. When
            // nothing's baked yet (a short stroke, or the first
            // `_kLiveBakeEvery` points of a new one) this is just the
            // whole line, same as before this layer existed.
            final int bakedCount = line.liveBakedPointCount;
            final int tailStart = bakedCount <= 0
                ? 0
                : (bakedCount - 3).clamp(0, line.points.length - 1);
            final Path livePath = _buildLivePathRange(
              line,
              tailStart,
              line.points.length,
            );
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

        // Draw a distinct pen tip at the very end of the stroke so viewers of
        // the recorded video can clearly see the exact drawing position.
        // Only shown during recording -- not on the live drawing screen.
        if (!line.isEraser && isRecording) {
          final Offset tipPos = line.points.last.offset;

          // Draw a small contrasting halo/shadow to make the tip pop against any line color
          final haloPaint = Paint()
            ..isAntiAlias = true
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0 / scale
            ..color = (isDark ? Colors.white : Colors.black).withValues(
              alpha: 0.3,
            );

          final tipPaint = Paint()
            ..isAntiAlias = true
            ..style = PaintingStyle.fill
            ..color = isDark ? Colors.white : Colors.black87;

          final double radius = (line.strokeWidth / 2) + (1.5 / scale);

          canvas.drawCircle(tipPos, radius, tipPaint);
          canvas.drawCircle(tipPos, radius, haloPaint);
        }
      }

      // 1b. Live eraser cursor ring -- see `_eraserCursorPos`'s doc comment:
      // this is the only visible feedback an in-progress area-eraser drag
      // gets (the actual clear-blend on `currentLine` above has no visible
      // effect on the finished layer underneath it, and the finished layer
      // itself no longer repaints mid-drag), so draw a simple ring at the
      // eraser's current position/size to show where it'll actually erase.
      if (eraserCursorPos != null) {
        final ringPaint = Paint()
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / scale
          ..color = (isDark ? Colors.white : Colors.black87).withValues(
            alpha: 0.55,
          );
        final fillPaint = Paint()
          ..isAntiAlias = true
          ..style = PaintingStyle.fill
          ..color = (isDark ? Colors.white : Colors.black87).withValues(
            alpha: 0.08,
          );
        canvas.drawCircle(eraserCursorPos!, eraserCursorRadius, fillPaint);
        canvas.drawCircle(eraserCursorPos!, eraserCursorRadius, ringPaint);
      }

      // 1c. Draw each selected line's actual content a second time, live,
      // on top of everything else. Layer 1a/1b
      // (`_MathsPadFinishedStrokesPainter`) skip a line entirely for as
      // long as it's selected (see that class's `selectedInThisLayer`
      // doc comment) -- this is the ONLY place a selected line's
      // ink/image actually gets drawn while selected. That's what makes
      // a selected item visually pop to the front of anything it
      // overlaps, and lets it track a live move/rotate/resize drag every
      // single frame without touching (or re-baking) the rest of the
      // page at all -- see `_onScaleUpdate`'s Move/Rotate/Resize
      // branches, which used to nuke every baked chunk on the page on
      // every drag-update frame just to move one line.
      _drawSelectedLinesOnTop(canvas);

      // 2. Draw each selected stroke's own neon outline, then the group
      // bounding box & handles on top of it.
      _drawNeonSelectionOutlines(canvas);
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

      // Laser Pointer trail -- always drawn last so it stays on top of
      // every stroke/selection/preview above.
      _drawLaserTrail(canvas);
    } finally {
      canvas.restore();
    }
  }

  /// Renders as a fixed *screen* size regardless of canvas zoom (dividing
  /// radii by `scale`, since `canvas` here is already inside the
  /// pan/zoom transform) -- a real laser pointer dot doesn't shrink when
  /// you zoom out on the content it's pointing at.
  void _drawLaserTrail(Canvas canvas) {
    if (laserTrail.isEmpty) return;
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    const double coreScreenRadius = 7.0;
    const double glowScreenRadius = 26.0;

    // Fading comet tail: older points shrink and fade out.
    for (int i = 0; i < laserTrail.length - 1; i++) {
      final p = laserTrail[i];
      final double age = (nowMs - p.bornAtMs) / _kLaserTrailLifetimeMs;
      if (age >= 1.0) continue;
      final double t = (1.0 - age).clamp(0.0, 1.0);
      final Paint tailPaint = Paint()
        ..isAntiAlias = true
        ..color = const Color(0xFFFF3B30).withValues(alpha: 0.45 * t);
      canvas.drawCircle(
        p.pos,
        (coreScreenRadius * 0.55 * t) / scale,
        tailPaint,
      );
    }

    // The current (newest) point gets the full glowing "hot" dot.
    final _LaserTrailPoint latest = laserTrail.last;
    final double latestAge = (nowMs - latest.bornAtMs) / _kLaserTrailLifetimeMs;
    if (latestAge >= 1.0) return;
    final double t = (1.0 - latestAge).clamp(0.0, 1.0);

    // Soft outer bloom.
    final Paint glowPaint = Paint()
      ..isAntiAlias = true
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10.0 / scale)
      ..color = const Color(0xFFFF3B30).withValues(alpha: 0.35 * t);
    canvas.drawCircle(latest.pos, glowScreenRadius / scale, glowPaint);

    // Bright gradient core (hot white centre fading to laser red).
    final double coreRadius = coreScreenRadius / scale;
    final Paint corePaint = Paint()
      ..isAntiAlias = true
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: t),
          const Color(0xFFFF453A).withValues(alpha: t),
          const Color(0xFFFF453A).withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: latest.pos, radius: coreRadius));
    canvas.drawCircle(latest.pos, coreRadius, corePaint);

    // A crisp thin ring on top reads as "sharp focus point" rather than
    // just a soft blob -- the touch of polish that makes it feel modern
    // rather than a plain flat dot.
    final Paint ringPaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4 / scale
      ..color = Colors.white.withValues(alpha: 0.85 * t);
    canvas.drawCircle(latest.pos, coreRadius * 0.55, ringPaint);
  }

  Path _buildLivePath(MathsPadLine line) {
    if (line.isPencil) {
      // Defensive fallback only (a committed pencil line always has
      // `cachedPath` set by `_buildAndCachePath` already) -- if it's ever
      // hit, stay on the Pencil tool's own outline geometry rather than
      // falling through to the Pen's centerline smoothing below.
      return _buildPencilOutlinePath(line, isComplete: true);
    }

    final path = Path();
    if (line.points.isEmpty) return path;

    path.moveTo(line.points[0].offset.dx, line.points[0].offset.dy);
    if (line.points.length == 2) {
      path.lineTo(line.points[1].offset.dx, line.points[1].offset.dy);
      return path;
    }

    // Shape tools (Square Tool, basic shape stamps, ...) want crisp straight
    // edges/sharp corners live while dragging, same as their final committed
    // path (`_buildAndCachePath`) already does -- only freehand pen strokes
    // should get the quadratic-smoothed curve treatment below.
    if (line.isShape) {
      for (int i = 1; i < line.points.length; i++) {
        path.lineTo(line.points[i].offset.dx, line.points[i].offset.dy);
      }
      return path;
    }

    // Chaikin-smooth the live preview too (same treatment
    // `_buildAndCachePath` gives the finished stroke), so the ink doesn't
    // visibly "settle"/refine the instant the pen lifts -- what you see
    // while drawing is what you get.
    //
    // Re-running the smoothing pass itself over EVERY point of the
    // stroke-so-far, on every single drawing frame, was the dominant
    // per-frame allocation source during a long freehand stroke (a fresh
    // `List<Offset>` plus, per Chaikin iteration, another list roughly 2x
    // the size of the last -- all discarded every frame just to add one
    // more point) -- felt as stutter that gets worse the longer a stroke
    // (and, via the resulting GC pressure, a whole session) runs. The
    // smoothed point set is cached on the line and only recomputed every
    // `_kLiveSmoothRebuildEvery` new points; in between, the path is
    // rebuilt from that cached smoothing plus one cheap straight segment
    // out to the actual newest point (Chaikin always preserves a curve's
    // first/last input point exactly, so `smoothPts.last` and the newest
    // raw point coincide the instant the cache IS fresh -- this is a
    // strict extension, not an approximation, when unstaled). The tail
    // reads as a short straight segment for at most a few frames during
    // fast drawing -- imperceptible in practice -- and none of this
    // touches the FINAL committed stroke, which `_buildAndCachePath`
    // always builds fresh (3 iterations, over the complete final point
    // set) once at commit, never from this live cache.
    final int rawCount = line.points.length;
    List<Offset> smoothPts;
    if (line.liveCachedSmoothPts != null &&
        rawCount >= line.liveCachedRawPointCount &&
        rawCount - line.liveCachedRawPointCount < _kLiveSmoothRebuildEvery) {
      smoothPts = line.liveCachedSmoothPts!;
    } else {
      final List<Offset> rawOffsets = line.points.map((p) => p.offset).toList();
      smoothPts = _chaikinSmooth(rawOffsets, iterations: 2);
      line.liveCachedSmoothPts = smoothPts;
      line.liveCachedRawPointCount = rawCount;
    }

    for (int i = 1; i < smoothPts.length - 1; i++) {
      final pPrev = smoothPts[i];
      final pNext = smoothPts[i + 1];
      final midX = (pPrev.dx + pNext.dx) / 2;
      final midY = (pPrev.dy + pNext.dy) / 2;
      path.quadraticBezierTo(pPrev.dx, pPrev.dy, midX, midY);
    }
    path.lineTo(line.points.last.offset.dx, line.points.last.offset.dy);
    return path;
  }

  /// Draws every selected line's actual content (see the call site's doc
  /// comment for why this needs to happen at all) -- images and ink both,
  /// using the exact same shared paint functions the finished-strokes
  /// layers use, so a selected line looks pixel-identical here to how it
  /// looked before selection, just now on top instead of wherever it
  /// normally sits in the page's chronological stacking order.
  void _drawSelectedLinesOnTop(Canvas canvas) {
    for (final line in selectedLines) {
      if (line.fillImage != null && line.fillWorldBounds != null) {
        _paintFillImage(canvas, line);
      } else {
        _paintInkLine(canvas, line);
      }
    }
  }

  // Neon mix used by every selected-stroke outline -- cycles through
  // several saturated hues (like RGB gaming-peripheral lighting) rather
  // than a single flat colour.
  static const List<Color> _neonMix = [
    Color(0xFFFF7A00), // neon orange
    Color(0xFFFF2E9A), // neon pink
    Color(0xFF00E5FF), // neon cyan/blue
    Color(0xFF39FF14), // neon green
    Color(0xFFFF7A00), // wrap back to orange
  ];
  static const List<double> _neonMixStops = [0.0, 0.25, 0.5, 0.75, 1.0];

  /// A very thin, solid, continuously-glowing outline traced *outside*
  /// each individually selected stroke's own silhouette -- offset clear of
  /// the ink itself (never drawn over it) -- so it's unmistakable exactly
  /// which strokes are selected, distinct from the indigo bounding
  /// box/handles `_drawSelectionOverlay` draws for group transforms. The
  /// neon colours continuously flow around the outline (via a slowly
  /// rotating gradient) -- no dashing, no opacity pulsing, just steady
  /// colour motion.
  void _drawNeonSelectionOutlines(Canvas canvas) {
    if (selectedLines.isEmpty) return;
    // Gap between the ink's own edge and the inner edge of the outline --
    // this (not the outline's own thickness) is what keeps it from ever
    // sitting on top of the stroke.
    final double standoff = 4.5 / scale;
    const double ringThickness = 1.6;

    for (final line in selectedLines) {
      final Rect? bounds = line.fillImage != null
          ? line.fillWorldBounds
          : (line.cachedBounds ?? _lineBounds(line));
      if (bounds == null) continue;
      final Shader neonShader = SweepGradient(
        colors: _neonMix,
        stops: _neonMixStops,
        transform: GradientRotation(selectionGlowPhase * 0.02),
      ).createShader(bounds.inflate(bounds.longestSide / 2 + 1));

      if (line.fillImage != null && line.fillWorldBounds != null) {
        // A filled region/pasted image -- ink covers the whole rect, so
        // the outline traces a rounded rect inflated well clear of it.
        final RRect ring = RRect.fromRectAndRadius(
          bounds.inflate(4.5 / scale),
          const Radius.circular(8),
        );
        // `fillWorldBounds` itself deliberately stays axis-aligned when
        // an image is rotated -- only `rotation` changes, applied
        // separately at paint time around the bounds' own center (see
        // `_paintFillImage`, and the doc comment on `_onScaleUpdate`'s
        // Rotate branch for why). The outline has to apply that same
        // rotation itself here, the same way, or it stays axis-aligned
        // while the image underneath visibly spins.
        final bool rotated = line.rotation != 0;
        if (rotated) {
          canvas.save();
          final Offset center = bounds.center;
          canvas.translate(center.dx, center.dy);
          canvas.rotate(line.rotation);
          canvas.translate(-center.dx, -center.dy);
        }
        _paintNeonRing(canvas, Path()..addRRect(ring), neonShader, 1.6 / scale);
        if (rotated) {
          canvas.restore();
        }
        continue;
      }

      final double strokeStandoff = line.strokeWidth * 0.5; // 50% of the stroke

      if (line.points.length == 1) {
        // A single dot -- ink is a filled circle, so the outline is just
        // a bigger concentric circle.
        final double radius = (line.strokeWidth / 2) + (strokeStandoff / 2);
        _paintNeonRing(
          canvas,
          Path()..addOval(
            Rect.fromCircle(center: line.points.first.offset, radius: radius),
          ),
          neonShader,
          strokeStandoff,
        );
        continue;
      }

      if (line.points.length < 2) continue;

      if (line.isPencil) {
        // Pencil's `cachedPath` is already a filled outline polygon (its
        // own true silhouette), not a zero-width centerline like Pen's --
        // stroking a centerline-based halo/punch here would double-count
        // the ink's own width. Instead: stroke along the polygon's own
        // boundary to lay down a band straddling it, then clear-fill the
        // polygon's interior to remove the inward half, leaving a ring
        // that hugs the pencil stroke's actual silhouette.
        final Path fillPath =
            line.cachedPath ?? _buildPencilOutlinePath(line, isComplete: true);
        final Rect layerBounds = bounds.inflate(strokeStandoff * 2 + 20);
        canvas.saveLayer(layerBounds, Paint());
        try {
          final Paint haloPaint = Paint()
            ..isAntiAlias = true
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = strokeStandoff * 2
            ..shader = neonShader;
          canvas.drawPath(fillPath, haloPaint);

          final Paint punchPaint = Paint()
            ..style = PaintingStyle.fill
            ..blendMode = BlendMode.clear;
          canvas.drawPath(fillPath, punchPaint);
        } finally {
          canvas.restore();
        }
        continue;
      }

      final Path centerline = line.cachedPath ?? _buildLivePath(line);

      // For an arbitrary freehand/shape stroke there's no simple "offset
      // this path outward" operation in dart:ui, so the standoff ring is
      // built by punching the ink's own footprint out of a wider halo:
      // draw a stroke wide enough to cover ink + standoff on both sides,
      // then clear back out exactly the ink's own width, leaving only the
      // outer band -- which never overlaps a single ink pixel.
      final Rect layerBounds = bounds.inflate(strokeStandoff * 2 + 20);
      canvas.saveLayer(layerBounds, Paint());
      try {
        final Paint haloPaint = Paint()
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = line.strokeWidth + strokeStandoff * 2
          ..shader = neonShader;
        canvas.drawPath(centerline, haloPaint);

        final Paint punchPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = line.strokeWidth
          ..blendMode = BlendMode.clear;
        canvas.drawPath(centerline, punchPaint);
      } finally {
        canvas.restore();
      }
    }
  }

  /// Draws [ringPath] (already offset clear of the ink it surrounds) as a
  /// soft glow plus a thin solid bright core, both coloured by the same
  /// continuously-rotating [neonShader] -- used for the dot/fill-image
  /// selection outlines, which (unlike an arbitrary freehand stroke) can
  /// be offset outward with simple geometry so they don't need the
  /// punch-a-hole compositing trick `_drawNeonSelectionOutlines` uses for
  /// freehand paths.
  void _paintNeonRing(
    Canvas canvas,
    Path ringPath,
    Shader neonShader,
    double coreWidth,
  ) {
    final Paint glowPaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = coreWidth * 4
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, coreWidth * 3)
      ..shader = neonShader;
    canvas.drawPath(ringPath, glowPaint);

    final Paint corePaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = coreWidth
      ..shader = neonShader;
    canvas.drawPath(ringPath, corePaint);
  }

  Rect? _lineBounds(MathsPadLine line) {
    if (line.points.isEmpty) return null;
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
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  void _drawSelectionOverlay(Canvas canvas) {
    final selectionBounds = _getGroupBounds(selectedLines);
    if (selectionBounds != null) {
      final double rotation = _selectedImageRotation;
      if (rotation != 0) {
        canvas.save();
        canvas.translate(selectionBounds.center.dx, selectionBounds.center.dy);
        canvas.rotate(rotation);
        canvas.translate(
          -selectionBounds.center.dx,
          -selectionBounds.center.dy,
        );
      }
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

      if (rotation != 0) {
        canvas.restore();
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

class _RecordingNeonBorder extends StatefulWidget {
  final bool showCameraIcon;
  const _RecordingNeonBorder({this.showCameraIcon = false});

  @override
  State<_RecordingNeonBorder> createState() => _RecordingNeonBorderState();
}

class _RecordingNeonBorderState extends State<_RecordingNeonBorder>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: Listenable.merge([_controller, _fadeController]),
          builder: (context, _) {
            if (_fadeController.isCompleted) {
              return const SizedBox.shrink();
            }
            final opacity = _fadeController.value < 0.66
                ? 1.0
                : (1.0 - ((_fadeController.value - 0.66) / 0.34)).clamp(
                    0.0,
                    1.0,
                  );
            return Opacity(
              opacity: opacity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.showCameraIcon)
                    Center(
                      child: Icon(
                        Icons.filter_center_focus,
                        size: 120,
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                  CustomPaint(
                    painter: _NeonBorderPainter(
                      angle: _controller.value * 2 * pi,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NeonBorderPainter extends CustomPainter {
  final double angle;
  _NeonBorderPainter({required this.angle});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(18));

    // Glow effect
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0)
      ..shader = SweepGradient(
        colors: [
          Colors.transparent,
          Colors.blue.withValues(alpha: 0.2),
          Colors.blue,
          Colors.orange,
          Colors.red,
          Colors.purple,
          Colors.lightGreen,
          Colors.yellow,
          Colors.transparent,
        ],
        stops: const [0.0, 0.05, 0.15, 0.31, 0.47, 0.63, 0.79, 0.95, 1.0],
        transform: GradientRotation(angle),
      ).createShader(rect);

    // Solid border core
    final corePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..shader = SweepGradient(
        colors: [
          Colors.transparent,
          Colors.blue.withValues(alpha: 0.2),
          Colors.blue,
          Colors.orange,
          Colors.red,
          Colors.purple,
          Colors.lightGreen,
          Colors.yellow,
          Colors.transparent,
        ],
        stops: const [0.0, 0.05, 0.15, 0.31, 0.47, 0.63, 0.79, 0.95, 1.0],
        transform: GradientRotation(angle),
      ).createShader(rect);

    canvas.drawRRect(rrect, glowPaint);
    canvas.drawRRect(rrect, corePaint);
  }

  @override
  bool shouldRepaint(covariant _NeonBorderPainter oldDelegate) {
    return oldDelegate.angle != angle;
  }
}

/// A custom Stack that bypasses Flutter's default bounds-checking during hit tests.
/// This allows interactive children (like text editors or instruments) to receive taps
/// even when panned far outside the Stack's original screen-sized layout bounds on the
/// infinite canvas.
class _UnconstrainedHitTestStack extends Stack {
  _UnconstrainedHitTestStack({
    Key? key,
    AlignmentGeometry alignment = AlignmentDirectional.topStart,
    TextDirection? textDirection,
    StackFit fit = StackFit.loose,
    Clip clipBehavior = Clip.hardEdge,
    List<Widget> children = const <Widget>[],
  }) : super(
         key: key,
         alignment: alignment,
         textDirection: textDirection,
         fit: fit,
         clipBehavior: clipBehavior,
         children: children,
       );

  @override
  RenderStack createRenderObject(BuildContext context) {
    return _RenderUnconstrainedHitTestStack(
      alignment: alignment,
      textDirection: textDirection ?? Directionality.maybeOf(context),
      fit: fit,
      clipBehavior: clipBehavior,
    );
  }
}

class _RenderUnconstrainedHitTestStack extends RenderStack {
  _RenderUnconstrainedHitTestStack({
    AlignmentGeometry alignment = AlignmentDirectional.topStart,
    TextDirection? textDirection,
    StackFit fit = StackFit.loose,
    Clip clipBehavior = Clip.hardEdge,
  }) : super(
         alignment: alignment,
         textDirection: textDirection,
         fit: fit,
         clipBehavior: clipBehavior,
       );

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    // Bypass the `size.contains(position)` check that a normal RenderBox does,
    // allowing hits to fall through to children far outside our layout bounds.
    if (hitTestChildren(result, position: position) || hitTestSelf(position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }
}
