import 'package:flutter/material.dart';
import '../models/robo_command.dart';
import '../models/robo_context.dart';
import '../parser/robo_parser.dart';
import '../widgets/robo_canvas.dart';

class RoboDrawingScreen extends StatefulWidget {
  final bool isInline;
  const RoboDrawingScreen({Key? key, this.isInline = false}) : super(key: key);

  @override
  State<RoboDrawingScreen> createState() => _RoboDrawingScreenState();
}

class _RoboDrawingScreenState extends State<RoboDrawingScreen> with SingleTickerProviderStateMixin {
  final RoboContext _ctx = RoboContext();
  final List<TextEditingController> _controllers = [];
  final List<RoboCommand> _commands = [];

  late AnimationController _animController;
  int _activeCommandIndex = -1;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _animController.addListener(() {
      setState(() {}); // Trigger repaint for animation
    });
    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _playNextCommand();
      }
    });

    // Add some default examples
    _addCommandRow("A=point(5, 5)");
    _addCommandRow("B=point(-5, -5)");
    _addCommandRow("a=line(A, B)");
    _addCommandRow("C=point(5, -5)");
    _addCommandRow("D=point(-5, 5)");
    _addCommandRow("b=polygon(A, B, C, D)");
    _addCommandRow("stroke(b, 4.0)");
    
    // Transform examples
    _addCommandRow("c=rotate(b, 45)");
    _addCommandRow("stroke(c, 2.0)");
    _addCommandRow("fade(c, 0.5)");
    
    _addCommandRow("d=dilate(c, 0.5, point(0,0))");
    _addCommandRow("stroke(d, 1.0)");
    
    // Math and Helper examples
    _addCommandRow("E=point(X(A), Y(D))");
    _addCommandRow("distAD=dist(A, D)");
    _addCommandRow("midpoint=interpolate(A, B, 0.5)");
    _addCommandRow("proj=project(C, a)");
    _addCommandRow("stroke(proj, 4.0)");
    
    // Advanced Geometry examples
    _addCommandRow("p1=perp(a, C, 15)");
    _addCommandRow("stroke(p1, 2.0)");
    _addCommandRow("pointtype('sphere')");
    _addCommandRow("F=intersect(a, p1)");
    _addCommandRow("ang=angle(A, F, 90, 1)");
    _addCommandRow("stroke(ang, 3.0)");
    
    // Algebraic & Plotting examples
    _addCommandRow("G=point(10, 2*sin(90))");
    _addCommandRow("wave=plot('sin(x)', -10, 10)");
    _addCommandRow("stroke(wave, 1.0)");
    _addCommandRow("fade(wave, 0.5)");
    _addCommandRow("circ=para('3*cos(t)', '3*sin(t)', 0, 360, 5)");
    _addCommandRow("stroke(circ, 2.0)");
    
    // Boolean Region Operations & Fill
    _addCommandRow("poly1=polygon(-5, -5, -1, -5, -1, -1, -5, -1)");
    _addCommandRow("poly2=polygon(-3, -3, 1, -3, 1, 1, -3, 1)");
    _addCommandRow("region_and=and(poly1, poly2)");
    _addCommandRow("stroke(region_and, 3.0)");
    _addCommandRow("fill(region_and)");
    _addCommandRow("fill(poly1, poly2)");
    _addCommandRow("fade(poly1, 0.2)");
    _addCommandRow("fade(poly2, 0.2)");
    
    // Complex Intersections
    _addCommandRow("c1=circle(point(4, 5), 2)");
    _addCommandRow("c2=circle(point(6, 5), 2)");
    _addCommandRow("i1=intersect(c1, c2, 1)");
    _addCommandRow("i2=intersect(c1, c2, 2)");
    _addCommandRow("pointtype('cross')");
    _addCommandRow("stroke(i1, 3.0)");
    _addCommandRow("stroke(i2, 3.0)");
    
    _parseAllCommands();
  }

  @override
  void dispose() {
    _animController.dispose();
    for (var c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addCommandRow([String text = ""]) {
    _controllers.add(TextEditingController(text: text));
    setState(() {});
  }

  void _parseAllCommands() {
    _commands.clear();
    _ctx.clear();

    for (var c in _controllers) {
      final cmd = RoboParser.parse(c.text);
      if (cmd != null) {
        _commands.add(cmd);
      }
    }
  }

  void _evaluateUpTo(int index) {
    _ctx.clear();
    for (int i = 0; i <= index && i < _commands.length; i++) {
      _commands[i].evaluate(_ctx);
    }
  }

  void _play() {
    if (_commands.isEmpty) return;
    _parseAllCommands();

    setState(() {
      _isPlaying = true;
      if (_activeCommandIndex < 0 || _activeCommandIndex >= _commands.length) {
        _activeCommandIndex = 0;
      }
      _evaluateUpTo(_activeCommandIndex);
    });
    _animController.forward(from: 0.0);
  }

  void _pause() {
    setState(() {
      _isPlaying = false;
    });
    _animController.stop();
  }

  void _playNextCommand() {
    if (!_isPlaying) return;

    if (_activeCommandIndex + 1 < _commands.length) {
      setState(() {
        _activeCommandIndex++;
        _evaluateUpTo(_activeCommandIndex);
      });
      _animController.forward(from: 0.0);
    } else {
      setState(() {
        _isPlaying = false;
        // Keep active index at the end to show fully static final frame
        _animController.value = 1.0; 
      });
    }
  }

  void _stepForward() {
    _pause();
    if (_activeCommandIndex < _commands.length - 1) {
      setState(() {
        _activeCommandIndex++;
        _evaluateUpTo(_activeCommandIndex);
        _animController.value = 1.0;
      });
    }
  }

  void _stepBackward() {
    _pause();
    if (_activeCommandIndex >= 0) {
      setState(() {
        _activeCommandIndex--;
        if (_activeCommandIndex >= 0) {
          _evaluateUpTo(_activeCommandIndex);
          _animController.value = 1.0;
        } else {
          _ctx.clear();
          _animController.value = 0.0;
        }
      });
    }
  }

  void _playRow(int index) {
    if (_commands.isEmpty) _parseAllCommands();
    if (index >= _commands.length) return;

    _pause(); // Stop whatever is playing

    setState(() {
      _isPlaying = false; // Do not auto-advance to the next command
      _activeCommandIndex = index;
      _evaluateUpTo(_activeCommandIndex);
    });
    _animController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.isInline ? null : AppBar(
        title: const Text('Robo Drawing'),
        backgroundColor: Colors.blueGrey.shade900,
        foregroundColor: Colors.white,
      ),
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 300,
            color: Colors.grey.shade100,
            child: Column(
              children: [
                // Toolbar
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  color: Colors.white,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.grey),
                        onPressed: () {
                          setState(() {
                            _controllers.clear();
                            _commands.clear();
                            _ctx.clear();
                            _activeCommandIndex = -1;
                            _addCommandRow();
                          });
                        },
                      ),
                      IconButton(
                        icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.green),
                        onPressed: _isPlaying ? _pause : _play,
                      ),
                      IconButton(
                        icon: const Icon(Icons.stop, color: Colors.red),
                        onPressed: () {
                          _pause();
                          setState(() {
                            _activeCommandIndex = -1;
                            _ctx.clear();
                            _animController.value = 0.0;
                          });
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: _stepBackward,
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: _stepForward,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Command List
                Expanded(
                  child: ListView.builder(
                    itemCount: _controllers.length,
                    itemBuilder: (context, index) {
                      bool isActive = index == _activeCommandIndex;
                      return Container(
                        color: isActive ? Colors.blue.withValues(alpha: 0.1) : Colors.transparent,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Row(
                          children: [
                            InkWell(
                              onTap: () => _playRow(index),
                              child: Padding(
                                padding: const EdgeInsets.all(4.0),
                                child: Icon(
                                  Icons.play_arrow,
                                  size: 20,
                                  color: isActive ? Colors.blue : Colors.grey,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _controllers[index],
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                                style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                                onChanged: (val) {
                                  _pause();
                                  _parseAllCommands();
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ElevatedButton(
                    onPressed: () => _addCommandRow(),
                    child: const Text('Add Command'),
                  ),
                ),
              ],
            ),
          ),
          // Canvas
          Expanded(
            child: Container(
              color: Colors.white,
              child: RoboCanvas(
                ctx: _ctx,
                commands: _commands,
                activeCommandIndex: _activeCommandIndex,
                animationProgress: _animController.value,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
