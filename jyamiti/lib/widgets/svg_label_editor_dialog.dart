import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/api_service.dart';
import 'latex_rich_text.dart';

class SvgLabelEditorDialog extends StatefulWidget {
  final String imagePath;
  final bool isSvg;
  final List<Map<String, dynamic>> initialLabels;
  final double aspectRatio;

  const SvgLabelEditorDialog({
    super.key,
    required this.imagePath,
    required this.isSvg,
    required this.initialLabels,
    this.aspectRatio = 4 / 3,
  });

  @override
  State<SvgLabelEditorDialog> createState() => _SvgLabelEditorDialogState();
}

class _SvgLabelEditorDialogState extends State<SvgLabelEditorDialog> {
  late List<Map<String, dynamic>> _labels;
  int? _selectedIndex;
  
  Offset? _dragStartGlobalPos;
  double? _dragStartLabelX;
  double? _dragStartLabelY;
  
  final List<Map<String, String>> _colorPalette = [
    {'name': 'White', 'hex': '#FFFFFF'},
    {'name': 'Black', 'hex': '#000000'},
    {'name': 'Indigo', 'hex': '#6366F1'},
    {'name': 'Emerald', 'hex': '#10B981'},
    {'name': 'Amber', 'hex': '#F59E0B'},
    {'name': 'Red', 'hex': '#EF4444'},
    {'name': 'Blue', 'hex': '#3B82F6'},
    {'name': 'Violet', 'hex': '#8B5CF6'},
    {'name': 'Teal', 'hex': '#14B8A6'},
    {'name': 'Pink', 'hex': '#EC4899'},
  ];

  @override
  void initState() {
    super.initState();
    // Deep copy initial labels
    _labels = widget.initialLabels.map((l) => Map<String, dynamic>.from(l)).toList();
    if (_labels.isNotEmpty) {
      _selectedIndex = 0;
    }
  }

  String _getImageUrl(String relativeUrl) {
    if (relativeUrl.isEmpty) return '';
    if (relativeUrl.startsWith('http://') || relativeUrl.startsWith('https://')) {
      return relativeUrl;
    }
    String origin = ApiService.baseUrl;
    if (origin.endsWith('/api')) {
      origin = origin.substring(0, origin.length - 4);
    }
    return '$origin/$relativeUrl';
  }

  Offset _getAlignmentOffset(String alignment) {
    switch (alignment) {
      case 'left':
        return const Offset(0.0, -0.5);
      case 'right':
        return const Offset(-1.0, -0.5);
      case 'center':
      default:
        return const Offset(-0.5, -0.5);
    }
  }

  Color _parseHexColor(String hexString) {
    if (hexString.isEmpty) return Colors.black;
    hexString = hexString.replaceAll('#', '');
    if (hexString.length == 6) {
      hexString = 'FF$hexString';
    }
    try {
      return Color(int.parse(hexString, radix: 16));
    } catch (_) {
      return Colors.black;
    }
  }

  void _addNewLabel(double pctX, double pctY) {
    final String newId = 'lbl_${DateTime.now().millisecondsSinceEpoch}';
    final Map<String, dynamic> newLabel = {
      'id': newId,
      'text': 'Label Text',
      'x': double.parse(pctX.toStringAsFixed(1)),
      'y': double.parse(pctY.toStringAsFixed(1)),
      'color': '#FFFFFF',
      'fontSize': 14,
      'fontWeight': 'normal',
      'alignment': 'center',
      'isVisible': true,
    };

    setState(() {
      _labels.add(newLabel);
      _selectedIndex = _labels.length - 1;
    });
  }

  void _deleteSelectedLabel() {
    if (_selectedIndex == null) return;
    setState(() {
      _labels.removeAt(_selectedIndex!);
      _selectedIndex = _labels.isNotEmpty ? 0 : null;
    });
  }

  Widget _renderImageOrSvg() {
    final fullUrl = _getImageUrl(widget.imagePath);

    if (widget.isSvg) {
      if (widget.imagePath.contains('<svg') || widget.imagePath.contains('<path')) {
        return SvgPicture.string(
          widget.imagePath,
          fit: BoxFit.contain,
        );
      }
      return SvgPicture.network(
        fullUrl,
        fit: BoxFit.contain,
        placeholderBuilder: (context) => const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: JyamitiLoader(strokeWidth: 1.5, color: Color(0xFF6366F1)),
          ),
        ),
        errorBuilder: (context, error, stackTrace) => const Icon(
          Icons.broken_image,
          color: Colors.white24,
          size: 24,
        ),
      );
    } else {
      return Image.network(
        fullUrl,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: JyamitiLoader(strokeWidth: 1.5, color: Color(0xFF6366F1)),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => const Icon(
          Icons.broken_image,
          color: Colors.white24,
          size: 24,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('SVG Label Editor', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1E293B),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _labels),
            child: const Text('Done', style: TextStyle(color: Color(0xFF818CF8), fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
      body: Flex(
        direction: isPortrait ? Axis.vertical : Axis.horizontal,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Editor Canvas Panel
          Expanded(
            flex: 3,
            child: Container(
              color: const Color(0xFF090D16),
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.0),
                    child: Text(
                      'Tap anywhere to add a label. Drag existing labels to reposition.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: AspectRatio(
                          aspectRatio: widget.aspectRatio,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B).withOpacity(0.3),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final double canvasWidth = constraints.maxWidth;
                                final double canvasHeight = constraints.maxHeight;

                                return GestureDetector(
                                  onTapUp: (details) {
                                    // Calculate relative coordinates
                                    final double pctX = (details.localPosition.dx / canvasWidth) * 100;
                                    final double pctY = (details.localPosition.dy / canvasHeight) * 100;
                                    _addNewLabel(pctX, pctY);
                                  },
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      // Render the background SVG/Image
                                      Positioned.fill(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(11),
                                          child: _renderImageOrSvg(),
                                        ),
                                      ),

                                      // Render positioned draggable labels
                                      ...List.generate(_labels.length, (idx) {
                                        final label = _labels[idx];
                                        final bool isSelected = _selectedIndex == idx;
                                        final double lx = (label['x'] as num).toDouble();
                                        final double ly = (label['y'] as num).toDouble();
                                        final String text = label['text'] ?? '';
                                        final String colorHex = label['color'] ?? '#FFFFFF';
                                        final double fSize = (label['fontSize'] as num?)?.toDouble() ?? 14.0;
                                        final double scaleFactor = canvasWidth / 400.0;
                                        final double scaledFontSize = fSize * scaleFactor;
                                        final String fWeight = label['fontWeight'] ?? 'normal';
                                        final String align = label['alignment'] ?? 'center';

                                        return Positioned(
                                          left: lx / 100 * canvasWidth,
                                          top: ly / 100 * canvasHeight,
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () {
                                              setState(() {
                                                _selectedIndex = idx;
                                              });
                                            },
                                            onPanStart: (details) {
                                              setState(() {
                                                _selectedIndex = idx;
                                                _dragStartGlobalPos = details.globalPosition;
                                                _dragStartLabelX = lx;
                                                _dragStartLabelY = ly;
                                              });
                                            },
                                            onPanUpdate: (details) {
                                              if (_dragStartGlobalPos == null || _dragStartLabelX == null || _dragStartLabelY == null) return;
                                              final double deltaX = details.globalPosition.dx - _dragStartGlobalPos!.dx;
                                              final double deltaY = details.globalPosition.dy - _dragStartGlobalPos!.dy;
                                              
                                              setState(() {
                                                double newX = _dragStartLabelX! + (deltaX / canvasWidth * 100);
                                                double newY = _dragStartLabelY! + (deltaY / canvasHeight * 100);
                                                label['x'] = double.parse(newX.clamp(0.0, 100.0).toStringAsFixed(1));
                                                label['y'] = double.parse(newY.clamp(0.0, 100.0).toStringAsFixed(1));
                                              });
                                            },
                                            onPanEnd: (details) {
                                              setState(() {
                                                _dragStartGlobalPos = null;
                                                _dragStartLabelX = null;
                                                _dragStartLabelY = null;
                                              });
                                            },
                                            child: FractionalTranslation(
                                              translation: _getAlignmentOffset(align),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                                decoration: BoxDecoration(
                                                  border: Border.all(
                                                    color: isSelected ? const Color(0xFF6366F1) : Colors.transparent,
                                                    width: 1.5,
                                                  ),
                                                  borderRadius: BorderRadius.circular(6),
                                                  color: isSelected ? const Color(0xFF6366F1).withOpacity(0.1) : Colors.transparent,
                                                ),
                                                child: LatexRichText(
                                                  text: text,
                                                  style: TextStyle(
                                                    color: _parseHexColor(colorHex),
                                                    fontSize: scaledFontSize,
                                                    fontWeight: fWeight == 'bold' ? FontWeight.bold : FontWeight.normal,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // 2. Control/Editor Properties Panel
          Expanded(
            flex: 2,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF1E293B),
                border: Border(
                  top: BorderSide(color: Colors.white10),
                  left: BorderSide(color: Colors.white10),
                ),
              ),
              child: _selectedIndex == null
                  ? const Center(
                      child: Text(
                        'Select a label or tap the canvas to add one',
                        style: TextStyle(color: Colors.white30, fontStyle: FontStyle.italic),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Edit Label (${_selectedIndex! + 1})',
                                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                                onPressed: _deleteSelectedLabel,
                              ),
                            ],
                          ),
                          const Divider(color: Colors.white10),
                          const SizedBox(height: 12),

                          // Text input
                          const Text('Label Text (supports LaTeX like \$x\$, \$\\theta\$)', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 8),
                          TextFormField(
                            key: ValueKey('text_key_${_selectedIndex!}'),
                            initialValue: _labels[_selectedIndex!]['text'],
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: const Color(0xFF0F172A),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onChanged: (val) {
                              setState(() {
                                _labels[_selectedIndex!]['text'] = val;
                              });
                            },
                          ),
                          const SizedBox(height: 16),

                          // Coordinates
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'X Pos: ${_labels[_selectedIndex!]['x']}%',
                                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  'Y Pos: ${_labels[_selectedIndex!]['y']}%',
                                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Font size (Slider)
                          Row(
                            children: [
                              const Text('Font Size: ', style: TextStyle(color: Colors.white70, fontSize: 12)),
                              Text(
                                '${(_labels[_selectedIndex!]['fontSize'] as num).toInt()}pt',
                                style: const TextStyle(color: Color(0xFF818CF8), fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ],
                          ),
                          Slider(
                            value: (_labels[_selectedIndex!]['fontSize'] as num).toDouble(),
                            min: 10,
                            max: 32,
                            divisions: 22,
                            activeColor: const Color(0xFF6366F1),
                            onChanged: (val) {
                              setState(() {
                                _labels[_selectedIndex!]['fontSize'] = val.toInt();
                              });
                            },
                          ),
                          const SizedBox(height: 12),

                          // Alignment & Weight
                          Row(
                            children: [
                              // Alignment Dropdown
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Alignment', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                    const SizedBox(height: 6),
                                    DropdownButtonFormField<String>(
                                      value: _labels[_selectedIndex!]['alignment'],
                                      dropdownColor: const Color(0xFF1E293B),
                                      style: const TextStyle(color: Colors.white),
                                      decoration: InputDecoration(
                                        filled: true,
                                        fillColor: const Color(0xFF0F172A),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      items: const [
                                        DropdownMenuItem(value: 'left', child: Text('Left')),
                                        DropdownMenuItem(value: 'center', child: Text('Center')),
                                        DropdownMenuItem(value: 'right', child: Text('Right')),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) {
                                          setState(() {
                                            _labels[_selectedIndex!]['alignment'] = val;
                                          });
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              
                              // Font weight (Bold/Normal)
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Font Weight', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                    const SizedBox(height: 6),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _labels[_selectedIndex!]['fontWeight'] == 'bold'
                                            ? const Color(0xFF6366F1)
                                            : const Color(0xFF0F172A),
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _labels[_selectedIndex!]['fontWeight'] =
                                              _labels[_selectedIndex!]['fontWeight'] == 'bold'
                                                  ? 'normal'
                                                  : 'bold';
                                        });
                                      },
                                      child: Center(
                                        child: Text(
                                          _labels[_selectedIndex!]['fontWeight'] == 'bold' ? 'Bold' : 'Normal',
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // Color selection
                          const Text('Text Color', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _colorPalette.map((col) {
                              final String hex = col['hex']!;
                              final bool isSelected = _labels[_selectedIndex!]['color'] == hex;
                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _labels[_selectedIndex!]['color'] = hex;
                                  });
                                },
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: _parseHexColor(hex),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected ? Colors.white : Colors.white12,
                                      width: isSelected ? 2.5 : 1.0,
                                    ),
                                    boxShadow: isSelected
                                        ? [BoxShadow(color: const Color(0xFF6366F1).withOpacity(0.5), blurRadius: 6)]
                                        : null,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
