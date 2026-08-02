import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/api_service.dart';
import 'latex_rich_text.dart';

class SvgLabelOverlay extends StatelessWidget {
  final String imagePath;
  final bool isSvg;
  final List<dynamic> labels;
  final double aspectRatio;
  final double? height;

  const SvgLabelOverlay({
    super.key,
    required this.imagePath,
    required this.isSvg,
    required this.labels,
    this.aspectRatio = 4 / 3,
    this.height,
  });

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
    if (hexString.isEmpty) {
      return Colors.black;
    }
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

  Widget _renderImageOrSvg() {
    final fullUrl = _getImageUrl(imagePath);

    if (isSvg) {
      if (imagePath.contains('<svg') || imagePath.contains('<path')) {
        return SvgPicture.string(
          imagePath,
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
    Widget content = LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final double height = constraints.maxHeight;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Base Image
            Positioned.fill(
              child: _renderImageOrSvg(),
            ),

            // Labels overlay
            ...labels.map((label) {
              final bool isVisible = label['isVisible'] ?? true;
              if (!isVisible) return const SizedBox.shrink();

              final double x = (label['x'] as num?)?.toDouble() ?? 0.0;
              final double y = (label['y'] as num?)?.toDouble() ?? 0.0;
              final String text = label['text'] ?? '';
              final String colorHex = label['color'] ?? '#000000';
              final double fontSize = (label['fontSize'] as num?)?.toDouble() ?? 14.0;
              final double scaleFactor = width / 400.0;
              final double scaledFontSize = fontSize * scaleFactor;
              final String fontWeight = label['fontWeight'] ?? 'normal';
              final String alignment = label['alignment'] ?? 'center';

              return Positioned(
                left: x / 100 * width,
                top: y / 100 * height,
                child: FractionalTranslation(
                  translation: _getAlignmentOffset(alignment),
                  child: LatexRichText(
                    text: text,
                    style: TextStyle(
                      color: _parseHexColor(colorHex),
                      fontSize: scaledFontSize,
                      fontWeight: fontWeight == 'bold' ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      },
    );

    if (height != null) {
      return SizedBox(
        height: height,
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: content,
        ),
      );
    }

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: content,
    );
  }
}
