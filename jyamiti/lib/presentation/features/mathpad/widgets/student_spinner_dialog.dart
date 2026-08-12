import 'dart:math';
import 'package:flutter/material.dart';

class StudentSpinnerDialog extends StatefulWidget {
  final List<dynamic> batches;

  const StudentSpinnerDialog({super.key, required this.batches});

  @override
  State<StudentSpinnerDialog> createState() => _StudentSpinnerDialogState();
}

class _StudentSpinnerDialogState extends State<StudentSpinnerDialog> with SingleTickerProviderStateMixin {
  dynamic _selectedBatch;
  late AnimationController _controller;
  late Animation<double> _animation;
  
  double _currentAngle = 0;
  String? _winnerName;

  @override
  void initState() {
    super.initState();
    if (widget.batches.isNotEmpty) {
      _selectedBatch = widget.batches.first;
    }
    
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    
    _controller.addListener(() {
      setState(() {
        _currentAngle = _animation.value;
      });
    });
    
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _calculateWinner();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<String> get _currentStudents {
    if (_selectedBatch == null) return [];
    final students = _selectedBatch['students'] as List?;
    if (students == null || students.isEmpty) return [];
    return students.map((s) => (s['name'] ?? 'Unknown').toString()).toList();
  }

  void _spin() {
    if (_currentStudents.isEmpty) return;
    
    setState(() {
      _winnerName = null;
    });

    final random = Random();
    // Spin at least 3 full circles, plus a random fraction
    final extraSpins = 3 + random.nextInt(3);
    final randomFraction = random.nextDouble() * 2 * pi;
    final targetAngle = _currentAngle + (extraSpins * 2 * pi) + randomFraction;

    _animation = Tween<double>(begin: _currentAngle, end: targetAngle).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _controller.forward(from: 0);
  }

  void _calculateWinner() {
    final students = _currentStudents;
    if (students.isEmpty) return;
    
    final sweepAngle = 2 * pi / students.length;
    final normalizedAngle = _currentAngle % (2 * pi);
    
    // The top pointer is at -pi/2 in our drawing space.
    final pointerAngle = (2 * pi - normalizedAngle) % (2 * pi);
    final winnerIndex = (pointerAngle / sweepAngle).floor() % students.length;
    
    setState(() {
      _winnerName = students[winnerIndex];
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final students = _currentStudents;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1E1E2C) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Student Spinner',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (widget.batches.isNotEmpty)
              DropdownButton<dynamic>(
                value: _selectedBatch,
                isExpanded: true,
                dropdownColor: isDark ? const Color(0xFF2A2A3C) : Colors.white,
                items: widget.batches.map((b) {
                  return DropdownMenuItem<dynamic>(
                    value: b,
                    child: Text(b['name'] ?? b['title'] ?? 'Unknown Batch'),
                  );
                }).toList(),
                onChanged: _controller.isAnimating ? null : (value) {
                  setState(() {
                    _selectedBatch = value;
                    _currentAngle = 0;
                    _winnerName = null;
                  });
                },
              )
            else
              const Text('No assigned batches found.'),
            
            const SizedBox(height: 32),
            
            if (students.isEmpty)
              const SizedBox(
                height: 250,
                child: Center(child: Text('No students in this batch.')),
              )
            else
              SizedBox(
                height: 250,
                width: 250,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.rotate(
                      angle: _currentAngle,
                      child: CustomPaint(
                        size: const Size(250, 250),
                        painter: _RoulettePainter(
                          students: students,
                          isDark: isDark,
                        ),
                      ),
                    ),
                    Positioned(
                      top: -12,
                      child: CustomPaint(
                        size: const Size(24, 24),
                        painter: _PointerPainter(),
                      ),
                    ),
                  ],
                ),
              ),
              
            const SizedBox(height: 24),
            
            SizedBox(
              height: 32,
              child: _winnerName != null
                  ? Text(
                      '🎉 $_winnerName 🎉',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            
            const SizedBox(height: 24),
            
            FilledButton.icon(
              onPressed: students.isEmpty || _controller.isAnimating ? null : _spin,
              icon: const Icon(Icons.casino_rounded),
              label: const Text('SPIN'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(200, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoulettePainter extends CustomPainter {
  final List<String> students;
  final bool isDark;

  _RoulettePainter({required this.students, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = size.width / 2;
    final sweepAngle = 2 * pi / students.length;

    final colors = [
      Colors.redAccent,
      Colors.blueAccent,
      Colors.greenAccent.shade700,
      Colors.orangeAccent,
      Colors.purpleAccent,
      Colors.tealAccent.shade700,
      Colors.amberAccent.shade700,
      Colors.pinkAccent,
    ];

    for (int i = 0; i < students.length; i++) {
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.fill;
        
      final startAngle = -pi / 2 + (i * sweepAngle);
      
      canvas.drawArc(rect, startAngle, sweepAngle, true, paint);
      
      final borderPaint = Paint()
        ..color = isDark ? const Color(0xFF1E1E2C) : Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawArc(rect, startAngle, sweepAngle, true, borderPaint);

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(startAngle + sweepAngle / 2);
      
      final textPainter = TextPainter(
        text: TextSpan(
          text: students[i].length > 12 ? '${students[i].substring(0, 10)}...' : students[i],
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout(maxWidth: radius - 30);
      
      canvas.translate(radius / 2 - textPainter.width / 2 + 10, -textPainter.height / 2);
      textPainter.paint(canvas, Offset.zero);
      
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _RoulettePainter oldDelegate) {
    return oldDelegate.students != students || oldDelegate.isDark != isDark;
  }
}

class _PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
      
    final borderPaint = Paint()
      ..color = Colors.black45
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final path = Path()
      ..moveTo(size.width / 2, size.height) // tip pointing down
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(path, paint);
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
