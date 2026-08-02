import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class ThemeReveal extends StatefulWidget {
  final Widget child;

  const ThemeReveal({super.key, required this.child});

  static ThemeRevealState of(BuildContext context) {
    return context.findAncestorStateOfType<ThemeRevealState>()!;
  }

  static Future<void> animate(BuildContext context, VoidCallback callback) {
    try {
      final state = context.findAncestorStateOfType<ThemeRevealState>();
      if (state != null) {
        final box = context.findRenderObject() as RenderBox?;
        final offset = box != null 
            ? box.localToGlobal(box.size.center(Offset.zero))
            : Offset(MediaQuery.of(context).size.width / 2, MediaQuery.of(context).size.height / 2);
        return state.triggerTransition(offset, callback);
      }
    } catch (_) {}
    callback();
    return Future.value();
  }

  @override
  ThemeRevealState createState() => ThemeRevealState();
}

class ThemeRevealState extends State<ThemeReveal> with SingleTickerProviderStateMixin {
  final GlobalKey _repaintBoundaryKey = GlobalKey();
  ui.Image? _screenshot;
  Offset _revealOffset = Offset.zero;
  bool _isDarkReveal = false;
  late AnimationController _animationController;

  late Animation<double> _curvedAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _curvedAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOutQuart,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> triggerTransition(Offset offset, VoidCallback callback) async {
    try {
      final isCurrentlyDark = Theme.of(context).brightness == Brightness.dark;
      final targetIsDark = !isCurrentlyDark;
      final boundary = _repaintBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: ui.PlatformDispatcher.instance.views.first.devicePixelRatio);

        setState(() {
          _screenshot = image;
          _revealOffset = offset;
          _isDarkReveal = !targetIsDark;
        });
        _animationController.reset();
        
        callback();
        
        await WidgetsBinding.instance.endOfFrame;
        
        await _animationController.forward();
        setState(() {
          _screenshot = null;
        });
      } else {
        callback();
      }
    } catch (e) {
      debugPrint('Theme reveal transition error: $e');
      callback();
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _repaintBoundaryKey,
      child: Stack(
        children: [
          widget.child,
          if (_screenshot != null)
            AnimatedBuilder(
              animation: _curvedAnimation,
              builder: (context, child) {
                return ClipPath(
                  clipper: CircularRevealClipper(
                    fraction: _isDarkReveal ? _curvedAnimation.value : (1.0 - _curvedAnimation.value),
                    center: _revealOffset,
                    isExpanding: _isDarkReveal,
                  ),
                  child: RawImage(
                    image: _screenshot,
                    fit: BoxFit.fill,
                    width: MediaQuery.of(context).size.width,
                    height: MediaQuery.of(context).size.height,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class CircularRevealClipper extends CustomClipper<Path> {
  final double fraction;
  final Offset center;
  final bool isExpanding;

  CircularRevealClipper({
    required this.fraction,
    required this.center,
    required this.isExpanding,
  });

  @override
  Path getClip(Size size) {
    final double maxRadius = _getFurthestDistance(size);
    final double radius = maxRadius * fraction;

    final path = Path();
    if (isExpanding) {
      path.addRect(Rect.fromLTWH(0, 0, size.width, size.height));
      final circlePath = Path()
        ..addOval(Rect.fromCircle(center: center, radius: radius));
      return Path.combine(PathOperation.difference, path, circlePath);
    } else {
      path.addOval(Rect.fromCircle(center: center, radius: radius));
      return path;
    }
  }

  double _getFurthestDistance(Size size) {
    final double d1 = (Offset.zero - center).distance;
    final double d2 = (Offset(size.width, 0) - center).distance;
    final double d3 = (Offset(0, size.height) - center).distance;
    final double d4 = (Offset(size.width, size.height) - center).distance;

    double max = d1;
    if (d2 > max) max = d2;
    if (d3 > max) max = d3;
    if (d4 > max) max = d4;
    return max;
  }

  @override
  bool shouldReclip(covariant CircularRevealClipper oldClipper) {
    return oldClipper.fraction != fraction || oldClipper.center != center || oldClipper.isExpanding != isExpanding;
  }
}
