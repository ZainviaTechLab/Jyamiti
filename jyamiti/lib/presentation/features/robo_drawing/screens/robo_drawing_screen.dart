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

    // Bisection of an angle example
    _addCommandRow("text('Construct a line which bisects an angle')");
    _addCommandRow("A=point(3,3)");
    _addCommandRow("B=point(14,3)");
    _addCommandRow("a=line(A,B)");
    _addCommandRow("b=line(A,9.5,14)");
    _addCommandRow("text('Draw an arc with center A of any radius')");
    _addCommandRow("c=arc(A,5,330,120)");
    _addCommandRow("C=point(intersect(a,c))");
    _addCommandRow("D=point(intersect(b,c))");
    _addCommandRow("text('Draw an arc with center C of any radius greather that half of CD')");
    _addCommandRow("d=arc(C,4,20,60)");
    _addCommandRow("text('Repeat this with center D using the same radius')");
    _addCommandRow("e=arc(D,4,330,60)");
    _addCommandRow("E=point(intersect(d,e))");
    _addCommandRow("text('Join A to the point where arcs cross.')");
    _addCommandRow("c=line(A,E)");
    _addCommandRow("findangle(b,c)");
    _addCommandRow("findangle(a,c)");
    
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
        
        // Adjust speed if overriden
        final cmd = _commands[_activeCommandIndex];
        if (cmd.assignedVar != null) {
          final obj = _ctx.variables[cmd.assignedVar!];
          if (obj?.speedOverride != null) {
            _animController.duration = Duration(milliseconds: (2000 / obj!.speedOverride!).round());
          } else {
            _animController.duration = const Duration(seconds: 2);
          }
        } else {
          _animController.duration = const Duration(seconds: 2);
        }
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
      
      // Adjust speed if overriden
      final cmd = _commands[_activeCommandIndex];
      if (cmd.assignedVar != null) {
        final obj = _ctx.variables[cmd.assignedVar!];
        if (obj?.speedOverride != null) {
          _animController.duration = Duration(milliseconds: (2000 / obj!.speedOverride!).round());
        } else {
          _animController.duration = const Duration(seconds: 2);
        }
      } else {
        _animController.duration = const Duration(seconds: 2);
      }
    });
    _animController.forward(from: 0.0);
  }

  void _showCommandSettingsDialog(int index) {
    if (_commands.isEmpty) _parseAllCommands();
    if (index >= _commands.length) return;
    final cmd = _commands[index];
    if (cmd.assignedVar == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("This command does not produce a named object to style.")));
      return;
    }
    final obj = _ctx.variables[cmd.assignedVar!];
    if (obj == null) return;

    showDialog(
      context: context,
      builder: (context) {
        Color selectedColor = obj.color;
        bool showLabel = obj.showLabel;
        double offsetX = obj.labelOffsetX;
        double offsetY = obj.labelOffsetY;
        double? speed = obj.speedOverride;
        String comment = obj.comment ?? "";
        
        TextEditingController offsetXController = TextEditingController(text: offsetX.toString());
        TextEditingController offsetYController = TextEditingController(text: offsetY.toString());
        TextEditingController commentController = TextEditingController(text: comment);

        return StatefulBuilder(
          builder: (context, setStateSB) {
            return AlertDialog(
              title: const Text('Settings'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Colors:"),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [Colors.blue, Colors.red, Colors.green, Colors.orange, Colors.purple, Colors.black].map((c) {
                        return InkWell(
                          onTap: () {
                            setStateSB(() => selectedColor = c);
                            setState(() => obj.color = c);
                          },
                          child: Container(
                            width: 24, height: 24,
                            decoration: BoxDecoration(color: c, border: Border.all(color: selectedColor == c ? Colors.blueAccent : Colors.transparent, width: 2)),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text("Show label: "),
                        Checkbox(
                          value: showLabel,
                          onChanged: (v) {
                            setStateSB(() => showLabel = v!);
                            setState(() => obj.showLabel = v!);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text("Label offset:"),
                    Row(
                      children: [
                        const Text("X: "),
                        SizedBox(width: 50, child: TextField(
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(isDense: true),
                          controller: offsetXController,
                          onSubmitted: (v) {
                            final val = double.tryParse(v);
                            if (val != null) {
                              setStateSB(() => offsetX = val);
                              setState(() => obj.labelOffsetX = val);
                            }
                          },
                        )),
                        const SizedBox(width: 16),
                        const Text("Y: "),
                        SizedBox(width: 50, child: TextField(
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(isDense: true),
                          controller: offsetYController,
                          onSubmitted: (v) {
                            final val = double.tryParse(v);
                            if (val != null) {
                              setStateSB(() => offsetY = val);
                              setState(() => obj.labelOffsetY = val);
                            }
                          },
                        )),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text("Comment:"),
                    TextField(
                      onChanged: (v) {
                        setStateSB(() => comment = v);
                        setState(() => obj.comment = v);
                      },
                      controller: commentController,
                    ),
                    const SizedBox(height: 16),
                    const Text("Speed:"),
                    Slider(
                      value: speed ?? 1.0,
                      min: 0.1,
                      max: 5.0,
                      onChanged: (v) {
                        setStateSB(() => speed = v);
                        setState(() => obj.speedOverride = v);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      }
    );
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
                            InkWell(
                              onTap: () => _showCommandSettingsDialog(index),
                              child: const Padding(
                                padding: EdgeInsets.all(4.0),
                                child: Icon(
                                  Icons.settings,
                                  size: 18,
                                  color: Colors.grey,
                                ),
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
