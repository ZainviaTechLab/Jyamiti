import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'package:flutter/material.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../services/api_service.dart';

class PdfAnnotationScreen extends StatefulWidget {
  final String url;
  final String filename;
  final String WorksheetId;
  final String submissionId;

  const PdfAnnotationScreen({
    super.key,
    required this.url,
    required this.filename,
    required this.WorksheetId,
    required this.submissionId,
  });

  @override
  State<PdfAnnotationScreen> createState() => _PdfAnnotationScreenState();
}

class _PdfAnnotationScreenState extends State<PdfAnnotationScreen> {
  final PdfViewerController _pdfViewerController = PdfViewerController();
  final UndoHistoryController _undoController = UndoHistoryController();
  bool _isSaving = false;

  bool _isPencilMode = false;
  bool _isEraserMode = false;
  List<List<Offset>> _strokes = [];
  List<List<Offset>> _redoStrokes = [];
  List<Offset> _currentStroke = [];
  final GlobalKey _pdfKey = GlobalKey();

  void _setAnnotationMode(PdfAnnotationMode mode) {
    setState(() {
      _isPencilMode = false; // Disable pencil when native tool selected
      _isEraserMode = false; // Disable eraser
      if (_pdfViewerController.annotationMode == mode) {
        _pdfViewerController.annotationMode = PdfAnnotationMode.none;
      } else {
        _pdfViewerController.annotationMode = mode;
      }
    });
  }

  void _togglePencilMode() {
    setState(() {
      _isPencilMode = !_isPencilMode;
      if (_isPencilMode) {
        _isEraserMode = false;
        _pdfViewerController.annotationMode = PdfAnnotationMode.none;
      }
    });
  }

  void _toggleEraserMode() {
    setState(() {
      _isEraserMode = !_isEraserMode;
      if (_isEraserMode) {
        _isPencilMode = false;
        _pdfViewerController.annotationMode = PdfAnnotationMode.none;
      }
    });
  }

  void _eraseStrokeAt(Offset position) {
    final absolutePosition = position + _pdfViewerController.scrollOffset;
    bool removed = false;
    for (int i = _strokes.length - 1; i >= 0; i--) {
      for (final point in _strokes[i]) {
        if ((point - absolutePosition).distance < 20.0) {
          final removedStroke = _strokes.removeAt(i);
          _redoStrokes.add(
            removedStroke,
          ); // allow undoing the erase! (Actually, this would restore it if we undo the erase, but let's keep it simple: just clearing redo stack for new actions)
          _redoStrokes.clear();
          removed = true;
          break;
        }
      }
      if (removed) break;
    }
    if (removed) {
      setState(() {});
    }
  }

  void _handleUndo() {
    if (_strokes.isNotEmpty) {
      setState(() {
        _redoStrokes.add(_strokes.removeLast());
      });
    } else if (_undoController.value.canUndo) {
      _undoController.undo();
    }
  }

  void _handleRedo() {
    if (_redoStrokes.isNotEmpty) {
      setState(() {
        _strokes.add(_redoStrokes.removeLast());
      });
    } else if (_undoController.value.canRedo) {
      _undoController.redo();
    }
  }

  Future<void> _saveAnnotations() async {
    setState(() => _isSaving = true);
    try {
      List<int> bytes = await _pdfViewerController.saveDocument();

      // Inject custom ink strokes if any
      if (_strokes.isNotEmpty) {
        final PdfDocument document = PdfDocument(inputBytes: bytes);

        RenderBox? box =
            _pdfKey.currentContext?.findRenderObject() as RenderBox?;
        if (box != null) {
          final Size screenSize = box.size;
          final double zoom = _pdfViewerController.zoomLevel;
          final Offset scroll = _pdfViewerController.scrollOffset;
          const int spacing = 4; // SfPdfViewer default spacing

          // Pre-calculate page offsets in screen pixels based on vertical layout
          List<double> pageStartOffsets = [];
          List<double> pageScreenHeights = [];
          double accumulatedHeight = 0;
          
          for (int i = 0; i < document.pages.count; i++) {
             final Size pSize = document.pages[i].size;
             // Assume page scales to fit screen width at zoomLevel 1.0
             final double pScreenHeight = (screenSize.width / pSize.width) * pSize.height * zoom;
             pageStartOffsets.add(accumulatedHeight);
             pageScreenHeights.add(pScreenHeight);
             accumulatedHeight += pScreenHeight + spacing;
          }

          for (final stroke in _strokes) {
            if (stroke.length < 2) continue;

            final Offset firstPoint = stroke.first;
            final double totalScreenY = firstPoint.dy;
            
            // Find which page this stroke belongs to
            int pageIndex = 0;
            for (int i = 0; i < pageStartOffsets.length; i++) {
               if (totalScreenY >= pageStartOffsets[i] && totalScreenY < pageStartOffsets[i] + pageScreenHeights[i] + spacing) {
                  pageIndex = i;
                  break;
               }
            }

            final PdfPage page = document.pages[pageIndex];
            final Size pdfSize = page.size;

            List<double> inkPoints = [];
            for (final point in stroke) {
              final double currentTotalY = point.dy;
              final double currentTotalX = point.dx;

              double localScreenY = currentTotalY - pageStartOffsets[pageIndex];
              double localScreenX = currentTotalX;

              // Convert to PDF coordinates
              double x = (localScreenX / (screenSize.width * zoom)) * pdfSize.width;
              double y = (localScreenY / pageScreenHeights[pageIndex]) * pdfSize.height;
              
              inkPoints.add(x);
              inkPoints.add(y);
            }

            final PdfPen pen = PdfPen(PdfColor(255, 0, 0), width: 3);
            if (inkPoints.length >= 4) {
              for (int i = 0; i < inkPoints.length - 2; i += 2) {
                page.graphics.drawLine(
                  pen,
                  Offset(inkPoints[i], inkPoints[i + 1]),
                  Offset(inkPoints[i + 2], inkPoints[i + 3]),
                );
              }
            } else if (inkPoints.length == 2) {
              page.graphics.drawRectangle(
                pen: pen,
                bounds: Rect.fromLTWH(inkPoints[0], inkPoints[1], 2, 2),
              );
            }
          }
        }

        bytes = await document.save();
        document.dispose();
      }

      final path =
          '/Worksheets/${widget.WorksheetId}/submissions/${widget.submissionId}/annotate';

      final res = await ApiService.uploadFile(
        path,
        bytes,
        'annotated_${widget.filename}',
        fieldName: 'pdf',
      );

      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Annotations saved successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to save annotations'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error saving PDF: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        title: Text(
          widget.filename,
          style: TextStyle(color: context.textColor, fontSize: 16),
        ),
        iconTheme: IconThemeData(color: context.textColor),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: JyamitiLoader(
                  color: Color(0xFF6366F1),
                  strokeWidth: 2,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.save_as_rounded, color: Color(0xFF10B981)),
              tooltip: 'Save Annotations',
              onPressed: _saveAnnotations,
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            color: context.isDark ? const Color(0xFF0F172A) : Colors.white,
            width: double.infinity,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.highlight,
                      color:
                          _pdfViewerController.annotationMode ==
                              PdfAnnotationMode.highlight
                          ? const Color(0xFF6366F1)
                          : Colors.white,
                    ),
                    tooltip: 'Highlight',
                    onPressed: () =>
                        _setAnnotationMode(PdfAnnotationMode.highlight),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.format_strikethrough,
                      color:
                          _pdfViewerController.annotationMode ==
                              PdfAnnotationMode.strikethrough
                          ? const Color(0xFF6366F1)
                          : Colors.white,
                    ),
                    tooltip: 'Strikethrough',
                    onPressed: () =>
                        _setAnnotationMode(PdfAnnotationMode.strikethrough),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.format_underline,
                      color:
                          _pdfViewerController.annotationMode ==
                              PdfAnnotationMode.underline
                          ? const Color(0xFF6366F1)
                          : Colors.white,
                    ),
                    tooltip: 'Underline',
                    onPressed: () =>
                        _setAnnotationMode(PdfAnnotationMode.underline),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.note_add,
                      color:
                          _pdfViewerController.annotationMode ==
                              PdfAnnotationMode.stickyNote
                          ? const Color(0xFF6366F1)
                          : Colors.white,
                    ),
                    tooltip: 'Sticky Note',
                    onPressed: () =>
                        _setAnnotationMode(PdfAnnotationMode.stickyNote),
                  ),
                  Container(
                    width: 1,
                    height: 24,
                    color: context.textColor54.withOpacity(0.4),
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.edit,
                      color: _isPencilMode
                          ? const Color(0xFF6366F1)
                          : Colors.white,
                    ),
                    tooltip: 'Pencil (Freehand)',
                    onPressed: _togglePencilMode,
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.cleaning_services_rounded,
                      color: _isEraserMode
                          ? const Color(0xFF6366F1)
                          : Colors.white,
                    ),
                    tooltip: 'Eraser (Erase Freehand)',
                    onPressed: _toggleEraserMode,
                  ),
                  Container(
                    width: 1,
                    height: 24,
                    color: context.textColor54.withOpacity(0.4),
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  ValueListenableBuilder<UndoHistoryValue>(
                    valueListenable: _undoController,
                    builder: (context, value, child) {
                      final canUndo = value.canUndo || _strokes.isNotEmpty;
                      return IconButton(
                        icon: const Icon(Icons.undo),
                        tooltip: 'Undo',
                        onPressed: canUndo ? _handleUndo : null,
                        color: canUndo ? Colors.white : Colors.white30,
                      );
                    },
                  ),
                  ValueListenableBuilder<UndoHistoryValue>(
                    valueListenable: _undoController,
                    builder: (context, value, child) {
                      final canRedo = value.canRedo || _redoStrokes.isNotEmpty;
                      return IconButton(
                        icon: const Icon(Icons.redo),
                        tooltip: 'Redo',
                        onPressed: canRedo ? _handleRedo : null,
                        color: canRedo ? Colors.white : Colors.white30,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        key: _pdfKey,
        children: [
          SfPdfViewer.network(
            widget.url,
            controller: _pdfViewerController,
            undoController: _undoController,
            canShowScrollHead: false,
            canShowScrollStatus: false,
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _pdfViewerController,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _PencilPainter(_strokes, _pdfViewerController.scrollOffset),
                    size: Size.infinite,
                  );
                },
              ),
            ),
          ),
          if (_isPencilMode || _isEraserMode)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (details) {
                  if (_isPencilMode) {
                    setState(() {
                      _currentStroke = [details.localPosition + _pdfViewerController.scrollOffset];
                      _strokes.add(_currentStroke);
                    });
                  } else if (_isEraserMode) {
                    _eraseStrokeAt(details.localPosition);
                  }
                },
                onPanUpdate: (details) {
                  if (_isPencilMode) {
                    setState(() {
                      _currentStroke.add(details.localPosition + _pdfViewerController.scrollOffset);
                    });
                  } else if (_isEraserMode) {
                    _eraseStrokeAt(details.localPosition);
                  }
                },
                onPanEnd: (details) {
                  if (_isPencilMode) {
                    setState(() {
                      _redoStrokes.clear();
                    });
                    _currentStroke = [];
                  }
                },
                child: Container(color: Colors.transparent),
              ),
            ),
        ],
      ),
      floatingActionButton:
          (_pdfViewerController.annotationMode != PdfAnnotationMode.none ||
              _isPencilMode ||
              _isEraserMode)
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFF6366F1),
              onPressed: () {
                setState(() {
                  _pdfViewerController.annotationMode = PdfAnnotationMode.none;
                  _isPencilMode = false;
                  _isEraserMode = false;
                });
              },
              icon: Icon(Icons.check, color: context.textColor),
              label: Text(
                'Done Annotating',
                style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold,
                ),
              ),
            ).animate().scale()
          : null,
    );
  }
}

class _PencilPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final Offset scrollOffset;

  _PencilPainter(this.strokes, this.scrollOffset);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      final path = Path();
      path.moveTo(stroke.first.dx - scrollOffset.dx, stroke.first.dy - scrollOffset.dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx - scrollOffset.dx, stroke[i].dy - scrollOffset.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PencilPainter oldDelegate) => true;
}

