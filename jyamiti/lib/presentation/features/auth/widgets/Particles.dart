import 'dart:math';
import 'package:flutter/material.dart';

class RotatingParticles extends StatefulWidget {
  final Widget child;
  final int particleCount;
  final double radius;
  final Duration duration;

  const RotatingParticles({
    Key? key,
    required this.child,
    this.particleCount = 10,
    this.radius = 140,
    this.duration = const Duration(seconds: 10),
  }) : super(key: key);

  @override
  State<RotatingParticles> createState() => _RotatingParticlesState();
}

class _RotatingParticlesState extends State<RotatingParticles>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // Main content centered
        widget.child,

        // Outer primary rotating particles
        ...List.generate(widget.particleCount, (index) {
          final angle = (index / widget.particleCount) * 2 * pi;
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final currentAngle = angle + _controller.value * 2 * pi;
              final dx = widget.radius * cos(currentAngle);
              final dy = widget.radius * sin(currentAngle);

              final isLarge = index % 2 == 0;
              final size = isLarge ? 8.0 : 5.0;
              final opacity =
                  0.4 +
                  0.4 * (0.5 + 0.5 * sin(_controller.value * 2 * pi + index));

              return Transform.translate(
                offset: Offset(dx, dy),
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        // const Color(0xFF6366F1).withOpacity(opacity),
                        // const Color(0xFFA78BFA).withOpacity(opacity),
                        const Color.fromARGB(
                          255,
                          8,
                          140,
                          28,
                        ).withOpacity(opacity),
                        const Color.fromARGB(
                          255,
                          100,
                          217,
                          102,
                        ).withOpacity(opacity),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        blurRadius: size * 2,
                        color: const Color.fromARGB(
                          255,
                          132,
                          206,
                          75,
                        ).withOpacity(0.5),
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        }),

        // Inner counter-rotating sparkle particles
        ...List.generate(6, (index) {
          final baseAngle = (index / 6) * 2 * pi + pi / 4;
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final angle = baseAngle - _controller.value * 2 * pi * 0.7;
              final distance =
                  widget.radius * 0.65 +
                  15 * sin(_controller.value * 2 * pi * 0.5 + index);
              final dx = distance * cos(angle);
              final dy = distance * sin(angle);
              final opacity =
                  0.5 + 0.4 * sin(_controller.value * 2 * pi + index);

              return Transform.translate(
                offset: Offset(dx, dy),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color.fromARGB(
                      255,
                      59,
                      223,
                      22,
                    ).withOpacity(opacity),
                    boxShadow: [
                      BoxShadow(
                        blurRadius: 6,
                        color: const Color.fromARGB(
                          255,
                          7,
                          174,
                          93,
                        ).withOpacity(0.4),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        }),
      ],
    );
  }
}
