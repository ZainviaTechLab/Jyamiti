import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../providers/theme_provider.dart';

class StrokePoint {
  Offset offset;
  StrokePoint(this.offset);
}

class DrawnLine {
  final List<StrokePoint> points;
  final Color color;
  final double strokeWidth;
  final bool isEraser;
  final bool isShape;

  Path? cachedPath;
  Rect? cachedBounds;

  DrawnLine({
    required this.points,
    required this.color,
    required this.strokeWidth,
    this.isEraser = false,
    this.isShape = false,
    this.cachedPath,
    this.cachedBounds,
  });

  void invalidateCache() {
    cachedPath = null;
    cachedBounds = null;
  }
}

enum CanvasToolMode { pen, eraser, tapSelect, lasso, pan }

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

class WritingPadWidget extends StatefulWidget {
  final VoidCallback? onClose;
  final bool isInline;
  final String? questionText;
  final bool isFullScreen;
  final VoidCallback? onToggleFullScreen;
  final bool isTransparentBg;

  const WritingPadWidget({
    super.key,
    this.onClose,
    this.isInline = true,
    this.questionText,
    this.isFullScreen = false,
    this.onToggleFullScreen,
    this.isTransparentBg = false,
  });

  @override
  State<WritingPadWidget> createState() => _WritingPadWidgetState();
}

class _WritingPadWidgetState extends State<WritingPadWidget>
    with SingleTickerProviderStateMixin {
  final List<DrawnLine> _lines = [];
  final List<DrawnLine> _undoHistory = [];
  DrawnLine? _currentLine;

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

  // ── 120 FPS Zero-Rebuild Pan & Zoom via ValueNotifiers ──────────────────
  // These bypass setState so panning NEVER triggers a widget tree rebuild.
  late final ValueNotifier<Offset> _panNotifier;
  late final ValueNotifier<double> _scaleNotifier;

  // Active Pointers tracking for Chrome Web Multi-Touch Panning
  final Map<int, Offset> _activePointers = {};
  Offset? _lastCentroid;

  // Hardware Stylus Side Barrel Button & Eraser Tip Detection
  bool _isStylusBarrelPressed = false;

  // Selected Lines & Move Drag State
  final Set<DrawnLine> _selectedLines = {};
  bool _isDraggingSelection = false;
  Offset? _lastDragWorldPos;

  // Stroke Clipboard for Copy (Ctrl+C) & Paste (Ctrl+V)
  List<DrawnLine> _clipboard = [];
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
    if (widget.isTransparentBg) {
      _bgMode = CanvasBgMode.blank;
    }
    _panNotifier = ValueNotifier<Offset>(_panOffset);
    _scaleNotifier = ValueNotifier<double>(_scale);
    _frictionController = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _canvasFocusNode.dispose();
    _panNotifier.dispose();
    _scaleNotifier.dispose();
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
  DrawnLine? _findLineAt(Offset worldPos) {
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
          });
        }
      } else {
        final bool isEraserStroke =
            _toolMode == CanvasToolMode.eraser || _isStylusBarrelPressed;
        final double activeWidth = isEraserStroke ? _eraserWidth : _penWidth;
        final newLine = DrawnLine(
          points: [StrokePoint(worldPos)],
          color: _selectedColor,
          strokeWidth: activeWidth,
          isEraser: isEraserStroke,
        );
        setState(() {
          _currentLine = newLine;
          _lines.add(newLine);
          _undoHistory.clear();
          _selectedLines.clear();
        });
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
    } else if (_activeShapeTool != null && _shapeDragStartPos != null) {
      final worldPos = _screenToWorld(details.localFocalPoint);
      setState(() {
        _shapeDragCurrentPos = worldPos;
      });
      return;
    } else if (_activeHandle != SelectionHandleType.none &&
        _transformStartPos != null) {
      // Active Selection Transformation: Move, Resize (Scale), or Rotate
      final worldPos = _screenToWorld(details.localFocalPoint);

      if (_activeHandle == SelectionHandleType.move) {
        final delta = worldPos - _transformStartPos!;
        setState(() {
          for (final line in _selectedLines) {
            for (int i = 0; i < line.points.length; i++) {
              line.points[i].offset += delta;
            }
            line.invalidateCache();
          }
          _transformStartPos = worldPos;
        });
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

        setState(() {
          for (final line in _selectedLines) {
            if (line.points.isEmpty) continue;

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
        });
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

          setState(() {
            for (final line in _selectedLines) {
              for (int i = 0; i < line.points.length; i++) {
                line.points[i].offset =
                    anchor + (line.points[i].offset - anchor) * scaleFactor;
              }
              line.invalidateCache();
            }
          });
        }
      }
      return;
    } else if ((_toolMode == CanvasToolMode.eraser || _isStylusBarrelPressed) &&
        _eraserMode == EraserMode.stroke) {
      // Stroke Eraser Mode: Dragging across stroke lines erases each whole line touched
      final worldPos = _screenToWorld(details.localFocalPoint);
      final hitLine = _findLineAt(worldPos);
      if (hitLine != null) {
        setState(() {
          _undoHistory.add(hitLine);
          _lines.remove(hitLine);
          _selectedLines.remove(hitLine);
        });
      }
      return;
    } else if (_isDraggingSelection && _lastDragWorldPos != null) {
      // Moving/dragging selected items in real time
      final worldPos = _screenToWorld(details.localFocalPoint);
      final delta = worldPos - _lastDragWorldPos!;
      setState(() {
        for (final line in _selectedLines) {
          for (int i = 0; i < line.points.length; i++) {
            line.points[i].offset += delta;
          }
        }
        _lastDragWorldPos = worldPos;
      });
    } else if (_toolMode == CanvasToolMode.lasso && _lassoPoints.isNotEmpty) {
      final worldPos = _screenToWorld(details.localFocalPoint);
      setState(() {
        _lassoPoints.add(worldPos);
      });
    } else if (_currentLine != null) {
      // 1-finger drawing stroke update
      final worldPos = _screenToWorld(details.localFocalPoint);
      if (_currentLine!.points.isEmpty ||
          (worldPos - _currentLine!.points.last.offset).distance >= 1.2) {
        setState(() {
          _currentLine!.points.add(StrokePoint(worldPos));
          _currentLine!.invalidateCache();
        });
      }
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
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

        setState(() {
          _lines.addAll(newShapeLines);
          _selectedLines.clear();
          _selectedLines.addAll(newShapeLines);
          _toolMode = CanvasToolMode.pen;
          _selectedWidth = _penWidth;
          _activeShapeTool = null;
        });
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

      final Set<DrawnLine> selectedContained = {};

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
    }

    // Trigger smooth inertial gliding velocity physics when flinging 2 fingers or Hand Tool
    if (_toolMode == CanvasToolMode.pan || _activePointers.length >= 2) {
      _startInertialFling(details.velocity.pixelsPerSecond);
    }

    setState(() {
      _currentLine = null;
    });
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
        return DrawnLine(
          points: line.points.map((p) => StrokePoint(p.offset)).toList(),
          color: line.color,
          strokeWidth: line.strokeWidth,
          isEraser: line.isEraser,
          isShape: line.isShape,
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

    final List<DrawnLine> pasted = _clipboard.map((line) {
      return DrawnLine(
        points: line.points
            .map((p) => StrokePoint(p.offset + translation))
            .toList(),
        color: line.color,
        strokeWidth: line.strokeWidth,
        isEraser: line.isEraser,
        isShape: line.isShape,
      );
    }).toList();

    setState(() {
      _lines.addAll(pasted);
      _undoHistory.clear();
      _selectedLines.clear();
      _selectedLines.addAll(pasted);
    });
  }

  // Duplicate Selected Strokes
  void _duplicateSelectedLines() {
    if (_selectedLines.isEmpty) return;

    final List<DrawnLine> duplicatedLines = [];
    const Offset copyOffset = Offset(25.0, 25.0);

    for (final line in _selectedLines) {
      final newPoints = line.points
          .map((p) => StrokePoint(p.offset + copyOffset))
          .toList();
      final newLine = DrawnLine(
        points: newPoints,
        color: line.color,
        strokeWidth: line.strokeWidth,
        isEraser: line.isEraser,
      );
      duplicatedLines.add(newLine);
    }

    setState(() {
      _lines.addAll(duplicatedLines);
      _undoHistory.addAll(duplicatedLines);
      _selectedLines.clear();
      _selectedLines.addAll(duplicatedLines);
    });
  }

  void _deleteSelectedLines() {
    if (_selectedLines.isNotEmpty) {
      setState(() {
        _undoHistory.addAll(_selectedLines);
        _lines.removeWhere((line) => _selectedLines.contains(line));
        _selectedLines.clear();
      });
    }
  }

  static List<DrawnLine> generateShapeLinesInRect(
    BasicShapeType shapeType,
    Rect rect,
    Color color,
    double strokeWidth,
  ) {
    final List<DrawnLine> createdLines = [];
    final Offset center = rect.center;
    final double radiusX = rect.width.abs() / 2;
    final double radiusY = rect.height.abs() / 2;

    switch (shapeType) {
      case BasicShapeType.circle:
        final List<StrokePoint> pts = [];
        for (int i = 0; i <= 64; i++) {
          final double a = (i / 64) * 2 * pi;
          pts.add(
            StrokePoint(center + Offset(cos(a) * radiusX, sin(a) * radiusY)),
          );
        }
        createdLines.add(
          DrawnLine(
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
          StrokePoint(squareRect.topLeft),
          StrokePoint(squareRect.topRight),
          StrokePoint(squareRect.bottomRight),
          StrokePoint(squareRect.bottomLeft),
          StrokePoint(squareRect.topLeft),
        ];
        createdLines.add(
          DrawnLine(
            points: pts,
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        break;

      case BasicShapeType.rectangle:
        final pts = [
          StrokePoint(rect.topLeft),
          StrokePoint(rect.topRight),
          StrokePoint(rect.bottomRight),
          StrokePoint(rect.bottomLeft),
          StrokePoint(rect.topLeft),
        ];
        createdLines.add(
          DrawnLine(
            points: pts,
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        break;

      case BasicShapeType.triangle:
        final pts = [
          StrokePoint(Offset(center.dx, rect.top)),
          StrokePoint(rect.bottomRight),
          StrokePoint(rect.bottomLeft),
          StrokePoint(Offset(center.dx, rect.top)),
        ];
        createdLines.add(
          DrawnLine(
            points: pts,
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        break;

      case BasicShapeType.rightTriangle:
        final pts = [
          StrokePoint(rect.bottomLeft),
          StrokePoint(rect.bottomRight),
          StrokePoint(rect.topLeft),
          StrokePoint(rect.bottomLeft),
        ];
        createdLines.add(
          DrawnLine(
            points: pts,
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        break;

      case BasicShapeType.pentagon:
        final List<StrokePoint> pts = [];
        for (int i = 0; i <= 5; i++) {
          final double a = (i / 5) * 2 * pi - pi / 2;
          pts.add(
            StrokePoint(center + Offset(cos(a) * radiusX, sin(a) * radiusY)),
          );
        }
        createdLines.add(
          DrawnLine(
            points: pts,
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        break;

      case BasicShapeType.hexagon:
        final List<StrokePoint> pts = [];
        for (int i = 0; i <= 6; i++) {
          final double a = (i / 6) * 2 * pi;
          pts.add(
            StrokePoint(center + Offset(cos(a) * radiusX, sin(a) * radiusY)),
          );
        }
        createdLines.add(
          DrawnLine(
            points: pts,
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        break;

      case BasicShapeType.diamond:
        final pts = [
          StrokePoint(Offset(center.dx, rect.top)),
          StrokePoint(Offset(rect.right, center.dy)),
          StrokePoint(Offset(center.dx, rect.bottom)),
          StrokePoint(Offset(rect.left, center.dy)),
          StrokePoint(Offset(center.dx, rect.top)),
        ];
        createdLines.add(
          DrawnLine(
            points: pts,
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        break;

      case BasicShapeType.star:
        final List<StrokePoint> pts = [];
        for (int i = 0; i < 10; i++) {
          final double rx = i.isEven ? radiusX : radiusX * 0.45;
          final double ry = i.isEven ? radiusY : radiusY * 0.45;
          final double a = (i / 10) * 2 * pi - pi / 2;
          pts.add(StrokePoint(center + Offset(cos(a) * rx, sin(a) * ry)));
        }
        pts.add(pts.first);
        createdLines.add(
          DrawnLine(
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
          DrawnLine(
            points: [
              StrokePoint(Offset(rect.left, center.dy)),
              StrokePoint(Offset(rect.right, center.dy)),
            ],
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        createdLines.add(
          DrawnLine(
            points: [
              StrokePoint(Offset(rect.right - 12, center.dy - 8)),
              StrokePoint(Offset(rect.right, center.dy)),
              StrokePoint(Offset(rect.right - 12, center.dy + 8)),
            ],
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );

        // Y-Axis with Arrowhead
        createdLines.add(
          DrawnLine(
            points: [
              StrokePoint(Offset(center.dx, rect.bottom)),
              StrokePoint(Offset(center.dx, rect.top)),
            ],
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        createdLines.add(
          DrawnLine(
            points: [
              StrokePoint(Offset(center.dx - 8, rect.top + 12)),
              StrokePoint(Offset(center.dx, rect.top)),
              StrokePoint(Offset(center.dx + 8, rect.top + 12)),
            ],
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        break;

      case BasicShapeType.arrowHorizontal:
        createdLines.add(
          DrawnLine(
            points: [
              StrokePoint(Offset(rect.left, center.dy)),
              StrokePoint(Offset(rect.right, center.dy)),
            ],
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        createdLines.add(
          DrawnLine(
            points: [
              StrokePoint(Offset(rect.right - 14, center.dy - 10)),
              StrokePoint(Offset(rect.right, center.dy)),
              StrokePoint(Offset(rect.right - 14, center.dy + 10)),
            ],
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        break;

      case BasicShapeType.arrowVertical:
        createdLines.add(
          DrawnLine(
            points: [
              StrokePoint(Offset(center.dx, rect.bottom)),
              StrokePoint(Offset(center.dx, rect.top)),
            ],
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        createdLines.add(
          DrawnLine(
            points: [
              StrokePoint(Offset(center.dx - 10, rect.top + 14)),
              StrokePoint(Offset(center.dx, rect.top)),
              StrokePoint(Offset(center.dx + 10, rect.top + 14)),
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
          DrawnLine(
            points: [
              StrokePoint(frontRect.topLeft),
              StrokePoint(frontRect.topRight),
              StrokePoint(frontRect.bottomRight),
              StrokePoint(frontRect.bottomLeft),
              StrokePoint(frontRect.topLeft),
            ],
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );

        // Back Face
        createdLines.add(
          DrawnLine(
            points: [
              StrokePoint(backRect.topLeft),
              StrokePoint(backRect.topRight),
              StrokePoint(backRect.bottomRight),
              StrokePoint(backRect.bottomLeft),
              StrokePoint(backRect.topLeft),
            ],
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );

        // 4 Connecting Edges
        createdLines.add(
          DrawnLine(
            points: [
              StrokePoint(frontRect.topLeft),
              StrokePoint(backRect.topLeft),
            ],
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        createdLines.add(
          DrawnLine(
            points: [
              StrokePoint(frontRect.topRight),
              StrokePoint(backRect.topRight),
            ],
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        createdLines.add(
          DrawnLine(
            points: [
              StrokePoint(frontRect.bottomRight),
              StrokePoint(backRect.bottomRight),
            ],
            color: color,
            strokeWidth: strokeWidth,
            isShape: true,
          ),
        );
        createdLines.add(
          DrawnLine(
            points: [
              StrokePoint(frontRect.bottomLeft),
              StrokePoint(backRect.bottomLeft),
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
        _undoHistory.add(_lines.removeLast());
        _selectedLines.clear();
      });
    }
  }

  void _redo() {
    if (_undoHistory.isNotEmpty) {
      setState(() {
        _lines.add(_undoHistory.removeLast());
        _selectedLines.clear();
      });
    }
  }

  void _clearCanvas() {
    setState(() {
      _lines.clear();
      _undoHistory.clear();
      _selectedLines.clear();
      _lassoPoints.clear();
    });
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
              child: ClipRRect(
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
                        // ValueListenableBuilder – repaints ONLY the canvas on pan/zoom
                        // without triggering any parent setState → pure 120 FPS panning!
                        child: ValueListenableBuilder<Offset>(
                          valueListenable: _panNotifier,
                          builder: (_, pan, child) {
                            return ValueListenableBuilder<double>(
                              valueListenable: _scaleNotifier,
                              builder: (_, sc, child) {
                                return RepaintBoundary(
                                  child: CustomPaint(
                                    size: Size.infinite,
                                    painter: _InfiniteWritingCanvasPainter(
                                      lines: _lines,
                                      selectedLines: _selectedLines,
                                      lassoPoints: _lassoPoints,
                                      bgMode: _bgMode,
                                      isDark: isDark,
                                      canvasBgColor: bgColor,
                                      panOffset: pan,
                                      scale: sc,
                                      activeShapeTool: _activeShapeTool,
                                      shapeDragStartPos: _shapeDragStartPos,
                                      shapeDragCurrentPos: _shapeDragCurrentPos,
                                      selectedColor: _selectedColor,
                                      penWidth: _penWidth,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
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

                        final String effectiveQText =
                            widget.questionText!.trim();

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
              ),
            ),
          ],
        ),
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
}

class _InfiniteWritingCanvasPainter extends CustomPainter {
  final List<DrawnLine> lines;
  final Set<DrawnLine> selectedLines;
  final List<Offset> lassoPoints;
  final CanvasBgMode bgMode;
  final bool isDark;
  final Color canvasBgColor;
  final Offset panOffset;
  final double scale;
  final BasicShapeType? activeShapeTool;
  final Offset? shapeDragStartPos;
  final Offset? shapeDragCurrentPos;
  final Color selectedColor;
  final double penWidth;

  _InfiniteWritingCanvasPainter({
    required this.lines,
    required this.selectedLines,
    required this.lassoPoints,
    required this.bgMode,
    required this.isDark,
    required this.canvasBgColor,
    required this.panOffset,
    required this.scale,
    this.activeShapeTool,
    this.shapeDragStartPos,
    this.shapeDragCurrentPos,
    this.selectedColor = const Color(0xFF6366F1),
    this.penWidth = 3.0,
  });

  Rect? _getGroupBounds(Set<DrawnLine> selection) {
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

  List<Offset> _chaikinSmooth(List<Offset> pts, {int iterations = 3}) {
    if (pts.length < 3) return pts;

    // 1. 3-Point Gaussian Low-Pass Filter to remove digitizer touch hardware jitter
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

    // 2. 3-Pass Chaikin Corner-Cutting Subdivision for silky $C^1$ curve continuity
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

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    try {
      // 1. Apply Infinite Viewport Transformation (Pan & Zoom)
      canvas.translate(panOffset.dx, panOffset.dy);
      canvas.scale(scale);

      // Calculate visible viewport bounds in World Coordinates
      final double startX = ((-panOffset.dx) / scale);
      final double endX = ((size.width - panOffset.dx) / scale);
      final double startY = ((-panOffset.dy) / scale);
      final double endY = ((size.height - panOffset.dy) / scale);

      // 2. Draw Infinite Background Grid / Lined Paper
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

      // 3. Viewport Spatial Culling Optimization using cached stroke bounds
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

      // 4. Render visible strokes (Only invoke expensive offscreen saveLayer if pixel eraser stroke is active)
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

      // 5. Draw Highlight Bounding Box & Control Handles around Selection Group
      _drawSelectionOverlay(canvas);
    } finally {
      canvas.restore();
    }
  }

  void _drawStrokes(Canvas canvas, List<DrawnLine> visibleLines) {
    for (final line in visibleLines) {
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
        // Compile & cache high-end Chaikin Subdivided Bezier Ink Curve once!
        if (line.cachedPath == null) {
          if (line.isShape || line.points.length <= 2) {
            final path = Path();
            path.moveTo(line.points[0].offset.dx, line.points[0].offset.dy);
            for (int i = 1; i < line.points.length; i++) {
              path.lineTo(line.points[i].offset.dx, line.points[i].offset.dy);
            }
            line.cachedPath = path;
          } else {
            final List<Offset> rawOffsets = line.points
                .map((p) => p.offset)
                .toList();
            final List<Offset> smoothPts = _chaikinSmooth(
              rawOffsets,
              iterations: 3,
            );

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
        }

        if (!line.isEraser) {
          // Soft dual-layer gel ink halo for ultra-polished, soft digital handwriting
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

      // Draw 4 Corner Resize Handles & Top Rotation Control Handle
      final Offset rotHandlePos = Offset(
        selectionBounds.center.dx,
        selectionBounds.top - 28.0 / scale,
      );

      // Stem line for Rotation Handle
      final stemPaint = Paint()
        ..color = const Color(0xFF6366F1)
        ..strokeWidth = 1.8 / scale
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(selectionBounds.center.dx, selectionBounds.top),
        rotHandlePos,
        stemPaint,
      );

      // Top Rotation Handle Knob (White Circle with Indigo Border)
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

      // 4 Corner Resize Control Handles
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

    // Draw Freehand Lasso Selection Loop if active
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

    // Draw Live Preview of Drag-to-Draw Shape Tool if actively dragging on canvas
    if (activeShapeTool != null &&
        shapeDragStartPos != null &&
        shapeDragCurrentPos != null) {
      final Rect shapeRect = Rect.fromPoints(
        shapeDragStartPos!,
        shapeDragCurrentPos!,
      );
      final previewLines = _WritingPadWidgetState.generateShapeLinesInRect(
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
          path.moveTo(line.points.first.offset.dx, line.points.first.offset.dy);
          for (int i = 1; i < line.points.length; i++) {
            path.lineTo(line.points[i].offset.dx, line.points[i].offset.dy);
          }
          canvas.drawPath(path, previewPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _InfiniteWritingCanvasPainter oldDelegate) {
    return true;
  }
}

class JyamitiPadFullScreenPage extends StatelessWidget {
  final String? questionText;

  const JyamitiPadFullScreenPage({super.key, this.questionText});

  static void open(BuildContext context, {String? questionText}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JyamitiPadFullScreenPage(questionText: questionText),
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
        child: WritingPadWidget(
          questionText: questionText,
          isFullScreen: true,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}

class JyamitiPadFab extends StatelessWidget {
  final VoidCallback? onPressed;
  final String heroTag;

  const JyamitiPadFab({
    super.key,
    this.onPressed,
    this.heroTag = 'jyamiti_pad_fab',
  });

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      heroTag: heroTag,
      onPressed: onPressed ?? () => JyamitiPadFullScreenPage.open(context),
      backgroundColor: const Color(0xFF10B981),
      elevation: 8,
      icon: const Icon(Icons.gesture_rounded, color: Colors.white, size: 22),
      label: const Text(
        'JyamitiPad',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
