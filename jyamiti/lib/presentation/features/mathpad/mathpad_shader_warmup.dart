import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/painting.dart';

/// Forces Skia to compile the specific GPU shader variants Math Pad's
/// canvas painting actually uses (`mathpad.dart`'s `_drawStrokes`/
/// `_buildLivePath`/`_drawNeonSelectionOutlines`/eraser compositing), once
/// at app startup, instead of the first real occurrence of each variant
/// stalling a frame mid-interaction.
///
/// This is the concrete fix for a "shader compilation jank" issue found via
/// a live DevTools Performance capture on a heavily-used Math Pad page: a
/// single frame spent 461ms in the Raster phase (budget is ~16ms), and
/// DevTools flagged "9 frames janked, 558.7ms total in shader compilation".
/// Skia compiles a GPU program for a given (blend mode, shader type, color
/// source, anti-aliasing, ...) combination the FIRST time that exact
/// combination is rasterized in a session -- a page that's used more tools/
/// colors/effects over its history is simply more likely to hit a
/// never-before-compiled combination on any given new stroke, which matches
/// "more strokes on the page = more lag" exactly (it's not that painting
/// itself gets slower with more strokes, it's that more distinct paint
/// configurations have been exercised on that page, raising the odds of a
/// cold-shader stall on whatever's drawn next) -- and explains why a blank
/// page felt smooth in the same running session (nothing novel to compile
/// yet) while the earlier algorithmic fixes (removing a redundant
/// full-canvas repaint during area-erasing, caching the live-stroke
/// smoothing pass) didn't help this specific symptom -- shader compilation
/// is a GPU-driver-level stall, an entirely different mechanism from either
/// of those.
///
/// A first pass covering only `mathpad.dart`'s own stroke/eraser/gradient
/// paint configs measurably reduced but didn't eliminate the jank (a
/// follow-up capture still showed 8 janked frames) -- the geometry
/// instruments (`ruler_widget.dart`/`protractor_widget.dart`/
/// `compass_widget.dart`/`set_square_widget.dart`) each have their own
/// distinct `Paint`/shader/text/image configurations (a `RadialGradient`
/// and second `LinearGradient` on the compass, `TextPainter` labels on all
/// four, `drawImageRect` for each instrument's logo watermark) that were
/// still cold. `--cache-sksl`/`--bundle-sksl-path` (Flutter's exhaustive
/// SkSL-capture-and-bundle workflow, the actually-complete fix) isn't
/// available for the `windows` target on this Flutter version (3.44.4),
/// nor is Impeller (`--enable-impeller` is explicitly a no-op on "other
/// platforms" per `flutter help run --verbose`) -- so a broadened manual
/// warm-up covering every distinct paint/text/image/blur configuration
/// actually used anywhere in Math Pad is the available fix here.
///
/// See <https://docs.flutter.dev/perf/shader> for the general technique.
class MathPadShaderWarmUp extends ShaderWarmUp {
  const MathPadShaderWarmUp();

  @override
  ui.Size get size => const ui.Size(200, 200);

  @override
  Future<void> warmUpOnCanvas(ui.Canvas canvas) async {
    // TEMPORARY diagnostic -- confirms this actually executes at startup
    // (check the console/terminal output where `flutter run` is attached).
    // Remove once confirmed.
    debugPrint('>>> MathPadShaderWarmUp.warmUpOnCanvas: START');

    final Path curvedPath = Path()
      ..moveTo(10, 100)
      ..quadraticBezierTo(50, 20, 90, 100)
      ..quadraticBezierTo(130, 180, 170, 100);

    // Plain solid-color freehand stroke -- the overwhelmingly common case
    // (`_buildLivePath`/`_buildAndCachePath`'s `quadraticBezierTo` path),
    // for a representative spread of stroke widths actually offered by the
    // pen-width picker.
    for (final width in [2.0, 4.0, 8.0, 14.0]) {
      canvas.drawPath(
        curvedPath,
        Paint()
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = width
          ..color = const Color(0xFF6366F1),
      );
    }

    // The semi-transparent "soft glow" stroke drawn under every live/
    // finished stroke (`_drawStrokes`/active-overlay paint) -- a
    // same-shape-different-alpha variant of the plain stroke above, which
    // still needs its own separate shader compile.
    canvas.drawPath(
      curvedPath,
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 10
        ..color = const Color(0xFF6366F1).withValues(alpha: 0.12),
    );

    // A single-point stroke (a dot / tap-to-place mark), filled circle.
    canvas.drawCircle(
      const Offset(150, 150),
      6,
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.fill
        ..color = const Color(0xFF10B981),
    );

    // Magic Pen's repeating diagonal rainbow `LinearGradient` shader.
    canvas.drawPath(
      curvedPath,
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 6
        ..shader = const LinearGradient(
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
        ).createShader(const Rect.fromLTWH(0, 0, 100, 100)),
    );

    // The neon selected-stroke outline's rotating `SweepGradient` shader.
    canvas.drawPath(
      Path()..addOval(const Rect.fromLTWH(20, 20, 160, 160)),
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..shader = const SweepGradient(
          colors: [
            Color(0xFFFF3B30),
            Color(0xFFFFD60A),
            Color(0xFF00E5FF),
            Color(0xFF39FF14),
            Color(0xFFFF3B30),
          ],
          stops: [0.0, 0.25, 0.5, 0.75, 1.0],
        ).createShader(const Rect.fromLTWH(0, 0, 200, 200)),
    );

    // The area eraser's actual compositing pattern: a `saveLayer` (its own
    // distinct GPU pipeline setup) containing an ordinary stroke UNDER a
    // `BlendMode.clear` stroke, matching `_drawStrokes`'s `hasPixelEraser`
    // branch exactly.
    canvas.saveLayer(const Rect.fromLTWH(0, 0, 200, 200), Paint());
    canvas.drawPath(
      curvedPath,
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 8
        ..color = const Color(0xFF6366F1),
    );
    canvas.drawPath(
      curvedPath,
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 20
        ..blendMode = BlendMode.clear,
    );
    canvas.restore();

    // The grid/ruled paper background -- `drawLine`, not `drawPath`, a
    // structurally different Skia draw op with its own shader.
    final Paint gridPaint = Paint()
      ..color = const Color(0xFF000000).withValues(alpha: 0.07)
      ..strokeWidth = 1.0;
    canvas.drawLine(const Offset(0, 0), const Offset(200, 0), gridPaint);
    canvas.drawLine(const Offset(0, 0), const Offset(0, 200), gridPaint);

    // Text labels (angle badges, ruler/protractor/set-square tick numbers,
    // text-tool labels) -- `drawParagraph`'s own distinct text-rendering
    // pipeline, never exercised by any of the path/shape draws above.
    final TextPainter textPainter = TextPainter(
      text: const TextSpan(text: '45°', style: TextStyle(color: Color(0xFF1E293B), fontSize: 14)),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, const Offset(10, 10));

    // Rounded-rect fill + stroke -- the instrument bodies (ruler/set-square/
    // protractor) and most toolbar/UI chrome use `RRect`, not the plain
    // `Rect`/circular shapes drawn above.
    final RRect rrect = RRect.fromRectAndRadius(const Rect.fromLTWH(20, 140, 100, 40), const Radius.circular(10));
    canvas.drawRRect(rrect, Paint()..color = const Color(0xFF1E293B));
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0x3DFFFFFF),
    );

    // The compass's radial gradient (its pivot hinge) -- a second gradient
    // type beyond the linear/sweep ones already covered above.
    canvas.drawCircle(
      const Offset(150, 40),
      15,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFE2E8F0), Color(0xFF94A3B8)],
        ).createShader(Rect.fromCircle(center: const Offset(150, 40), radius: 15)),
    );

    // Every geometry instrument (ruler/protractor/set-square) stamps a
    // small logo watermark via `drawImageRect` with reduced opacity --
    // needs a real decoded `ui.Image`, unlike every draw call above.
    final ui.Image tinyImage = await _tinyImage();
    canvas.drawImageRect(
      tinyImage,
      Rect.fromLTWH(0, 0, tinyImage.width.toDouble(), tinyImage.height.toDouble()),
      const Rect.fromLTWH(60, 140, 40, 40),
      Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.55),
    );
    tinyImage.dispose();

    // The frosted-glass text editor / dialog backgrounds use
    // `ImageFilter.blur` -- a backdrop-filter pipeline distinct from every
    // plain-color/gradient/text/image draw above.
    canvas.saveLayer(
      const Rect.fromLTWH(0, 0, 200, 200),
      Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
    );
    canvas.drawRect(const Rect.fromLTWH(0, 0, 200, 200), Paint()..color = const Color(0x1F000000));
    canvas.restore();

    debugPrint('>>> MathPadShaderWarmUp.warmUpOnCanvas: DONE');
  }

  Future<ui.Image> _tinyImage() {
    final completer = Completer<ui.Image>();
    final pixels = Uint8List.fromList(List.filled(4 * 4 * 4, 200));
    ui.decodeImageFromPixels(pixels, 4, 4, ui.PixelFormat.rgba8888, completer.complete);
    return completer.future;
  }
}
