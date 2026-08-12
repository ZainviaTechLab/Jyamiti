import re
import sys

path = r"c:\Users\USER\Desktop\myprojects\JyamitiApp\jyamiti\lib\presentation\features\mathpad\screens\mathpad.dart"
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add _isMagicPenMode state
if "bool _isMagicPenMode = false;" not in content:
    content = content.replace(
        "CanvasToolMode _toolMode = CanvasToolMode.pen;",
        "CanvasToolMode _toolMode = CanvasToolMode.pen;\n  bool _isMagicPenMode = false;"
    )

# 2. Update MathsPadLine to include isMagic
if "final bool isMagic;" not in content:
    content = content.replace(
        "final double strokeWidth;",
        "final double strokeWidth;\n  final bool isMagic;"
    )
    content = content.replace(
        "this.strokeWidth = 3.0,",
        "this.strokeWidth = 3.0,\n    this.isMagic = false,"
    )

# 3. Update instantiation in _onScaleStart
target_inst = """        final newLine = MathsPadLine(
          points: [MathsPadStrokePoint(worldPos)],
          color: _selectedColor,
          strokeWidth: activeWidth,
          isEraser: isEraserStroke,
        );"""
repl_inst = """        final newLine = MathsPadLine(
          points: [MathsPadStrokePoint(worldPos)],
          color: _selectedColor,
          strokeWidth: activeWidth,
          isEraser: isEraserStroke,
          isMagic: !isEraserStroke && _toolMode == CanvasToolMode.pen && _isMagicPenMode,
        );"""
content = content.replace(target_inst, repl_inst)

# 4. Update Quick Toolbar toggle
quick_tb_orig = """                icon: Icons.edit_rounded,
                iconColor: iconColor,
                isSelected: _toolMode == CanvasToolMode.pen,
                onTap: () => setState(() {
                  _toolMode = CanvasToolMode.pen;
                  _activeShapeTool = null;
                }),"""
quick_tb_repl = """                icon: _toolMode == CanvasToolMode.pen && _isMagicPenMode ? Icons.auto_fix_high_rounded : Icons.edit_rounded,
                iconColor: iconColor,
                isSelected: _toolMode == CanvasToolMode.pen,
                onTap: () => setState(() {
                  if (_toolMode == CanvasToolMode.pen && _activeShapeTool == null) {
                    _isMagicPenMode = !_isMagicPenMode;
                  } else {
                    _toolMode = CanvasToolMode.pen;
                    _activeShapeTool = null;
                  }
                }),"""
content = content.replace(quick_tb_orig, quick_tb_repl)

# 5. Update Main Toolbar toggle
main_tb_orig = """                            icon: Icons.edit_rounded,
                            tooltip: 'Pen Mode',
                            isSelected:
                                _toolMode == CanvasToolMode.pen &&
                                _activeShapeTool == null,
                            onTap: () => setState(() {
                              _toolMode = CanvasToolMode.pen;
                              _activeShapeTool = null;
                              _selectedWidth = _penWidth;
                            }),"""
main_tb_repl = """                            icon: _toolMode == CanvasToolMode.pen && _isMagicPenMode ? Icons.auto_fix_high_rounded : Icons.edit_rounded,
                            tooltip: 'Pen Mode (Tap again for Magic Pen)',
                            isSelected:
                                _toolMode == CanvasToolMode.pen &&
                                _activeShapeTool == null,
                            onTap: () => setState(() {
                              if (_toolMode == CanvasToolMode.pen && _activeShapeTool == null) {
                                _isMagicPenMode = !_isMagicPenMode;
                              } else {
                                _toolMode = CanvasToolMode.pen;
                                _activeShapeTool = null;
                                _selectedWidth = _penWidth;
                              }
                            }),"""
content = content.replace(main_tb_orig, main_tb_repl)

# 6. Turn off Magic Pen if a color is selected in quick toolbar
content = content.replace(
"""                    _selectedColor = color;
                    _toolMode = CanvasToolMode.pen;
                    _activeShapeTool = null;
                  });""",
"""                    _selectedColor = color;
                    _toolMode = CanvasToolMode.pen;
                    _activeShapeTool = null;
                    _isMagicPenMode = false;
                  });"""
)

# 7. Turn off Magic Pen if a color is selected in main toolbar
content = content.replace(
"""                            _selectedColor = color;
                            _toolMode = CanvasToolMode.pen;
                            _activeShapeTool = null;
                            _selectedWidth = _penWidth;""",
"""                            _selectedColor = color;
                            _toolMode = CanvasToolMode.pen;
                            _activeShapeTool = null;
                            _selectedWidth = _penWidth;
                            _isMagicPenMode = false;"""
)

# 8. Disable Auto-Straighten when magic pen is active
content = content.replace(
"""      if (!_isEraser && _toolMode == CanvasToolMode.pen) {
        if (!_penAutoStraightened &&""",
"""      if (!_isEraser && _toolMode == CanvasToolMode.pen && !(_currentLine?.isMagic ?? false)) {
        if (!_penAutoStraightened &&"""
)

# 9. Painting logic
paint_orig = """      if (line.isEraser) {
        paint.blendMode = BlendMode.clear;
        paint.color = Colors.transparent;
      } else {
        paint.blendMode = BlendMode.srcOver;
        paint.color = line.color;
      }"""
paint_repl = """      if (line.isEraser) {
        paint.blendMode = BlendMode.clear;
        paint.color = Colors.transparent;
      } else {
        paint.blendMode = BlendMode.srcOver;
        if (line.isMagic && line.points.isNotEmpty) {
          paint.shader = const SweepGradient(
            colors: [
              Color(0xFFFF7A00),
              Color(0xFFFF2E9A),
              Color(0xFF00E5FF),
              Color(0xFF39FF14),
              Color(0xFFFF7A00),
            ],
          ).createShader(Rect.fromCircle(center: line.points.first.offset, radius: 1000));
        } else {
          paint.shader = null;
          paint.color = line.color;
        }
      }"""
content = content.replace(paint_orig, paint_repl)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Done")
