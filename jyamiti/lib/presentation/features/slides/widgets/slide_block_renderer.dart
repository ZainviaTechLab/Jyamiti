import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../../domain/models/slide_deck_models.dart';
import 'svg_style_inliner.dart';

class SlideBlockRenderer extends StatelessWidget {
  final SlideBlock block;
  final bool isDark;

  const SlideBlockRenderer({
    super.key,
    required this.block,
    this.isDark = true,
  });

  @override
  Widget build(BuildContext context) {
    switch (block.type) {
      case SlideBlockType.heading:
        return _buildHeading(context);
      case SlideBlockType.subheading:
        return _buildSubheading(context);
      case SlideBlockType.paragraph:
        return _buildParagraph(context);
      case SlideBlockType.code:
        return _buildCodeBlock(context);
      case SlideBlockType.bulletList:
        return _buildBulletList(context);
      case SlideBlockType.callout:
        return _buildCallout(context);
      case SlideBlockType.imageUrl:
        return _buildImageBlock(context);
      case SlideBlockType.math:
        return _buildMathBlock(context);
      case SlideBlockType.svg:
        return _buildSvgBlock(context);
    }
  }

  Widget _buildHeading(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0, top: 8.0),
      child: ShaderMask(
        shaderCallback: (bounds) => LinearGradient(
          colors: isDark
              ? [
                  const Color.fromARGB(255, 255, 255, 255),
                  const Color.fromARGB(255, 255, 255, 255),
                ]
              : [
                  const Color.fromARGB(255, 37, 37, 138),
                  const Color.fromARGB(255, 218, 199, 251),
                ],
        ).createShader(bounds),
        child: Text(
          block.content,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            height: 1.25,
            letterSpacing: -0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildSubheading(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10.0, top: 6.0),
      padding: const EdgeInsets.only(left: 10.0),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Color(0xFF6366F1), width: 3.5)),
      ),
      child: Text(
        block.content,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white : const Color(0xFF1E293B),
        ),
      ),
    );
  }

  Widget _buildParagraph(BuildContext context) {
    final text = block.content;
    final mathRegex = RegExp(r'(\$\$[\s\S]*?\$\$|\$[^\$\n]+?\$)');

    if (!mathRegex.hasMatch(text)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12.0),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 15.5,
            height: 1.55,
            color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
            fontWeight: FontWeight.w400,
          ),
        ),
      );
    }

    final spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final match in mathRegex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(
          TextSpan(
            text: text.substring(lastEnd, match.start),
            style: TextStyle(
              fontSize: 15.5,
              height: 1.55,
              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
              fontWeight: FontWeight.w400,
            ),
          ),
        );
      }

      final matchedStr = match.group(0)!;
      final isDisplay = matchedStr.startsWith(r'$$');
      final cleanTex = isDisplay
          ? matchedStr.substring(2, matchedStr.length - 2).trim()
          : matchedStr.substring(1, matchedStr.length - 1).trim();

      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Math.tex(
              cleanTex,
              textStyle: TextStyle(
                fontSize: 16.5,
                color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF4338CA),
                fontWeight: FontWeight.w600,
              ),
              onErrorFallback: (_) => Text(
                matchedStr,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  color: Colors.amber,
                ),
              ),
            ),
          ),
        ),
      );

      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(lastEnd),
          style: TextStyle(
            fontSize: 15.5,
            height: 1.55,
            color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
            fontWeight: FontWeight.w400,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: SelectableText.rich(
        TextSpan(children: spans),
      ),
    );
  }

  Widget _buildSvgBlock(BuildContext context) {
    final processedSvg = SvgStyleInliner.process(block.content);
    final dim = SvgStyleInliner.extractDimensions(processedSvg);
    final mode = (block.extra ?? 'full').toLowerCase().trim();

    final isOriginal = mode == 'original' ||
        mode == 'viewbox' ||
        mode == 'intrinsic' ||
        mode == 'native';
    final isBoxed = mode == 'boxed' || mode == 'contained' || mode == 'card';
    final isCompact = mode == 'compact' || mode == '75%';
    final isSmall = mode == 'small' || mode == '50%';

    Widget svgCore = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: dim.aspectRatio,
        child: SvgPicture.string(
          processedSvg,
          fit: BoxFit.contain,
          placeholderBuilder: (ctx) => const Padding(
            padding: EdgeInsets.all(24.0),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
    );

    if (isBoxed) {
      svgCore = Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0B2240) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? const Color(0xFF1E3A5F) : const Color(0xFFCBD5E1),
            width: 1.5,
          ),
        ),
        padding: const EdgeInsets.all(8.0),
        child: svgCore,
      );
    }

    // 1. Original / Native ViewBox dimensions mode
    if (isOriginal && dim.width != null && dim.height != null) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 12.0),
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: dim.width!,
            maxHeight: dim.height!,
          ),
          child: svgCore,
        ),
      );
    }

    // 2. Proportional Scaling / Full-Width modes
    double? widthFactor;
    if (isSmall) {
      widthFactor = 0.50;
    } else if (isCompact) {
      widthFactor = 0.75;
    } else if (isBoxed) {
      widthFactor = 0.85;
    } else if (mode.endsWith('%')) {
      final parsed = double.tryParse(mode.replaceAll('%', '').trim());
      if (parsed != null && parsed > 0 && parsed <= 100) {
        widthFactor = parsed / 100.0;
      }
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 12.0),
      alignment: Alignment.center,
      child: widthFactor != null
          ? FractionallySizedBox(
              widthFactor: widthFactor,
              child: svgCore,
            )
          : svgCore,
    );
  }

  Widget _buildCodeBlock(BuildContext context) {
    final lang = block.extra ?? 'code';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12.0),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.code_rounded,
                  size: 16,
                  color: Color(0xFF38BDF8),
                ),
                const SizedBox(width: 8),
                Text(
                  lang.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF38BDF8),
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 1.0,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: block.content));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Code copied to clipboard!'),
                        duration: Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.copy_rounded,
                          size: 14,
                          color: Color(0xFF94A3B8),
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Copy',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Code Text Area
          Padding(
            padding: const EdgeInsets.all(14.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                block.content,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13.5,
                  height: 1.45,
                  color: Color(0xFFE2E8F0),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBulletList(BuildContext context) {
    final List<String> items = block.content.contains('\n')
        ? block.content.split('\n').where((s) => s.trim().isNotEmpty).toList()
        : [block.content];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items.map((item) {
          final cleanItem = item.replaceFirst(RegExp(r'^[-*•]\s*'), '');
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 6, right: 10),
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Color(0xFF6366F1),
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Text(
                    cleanItem,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      color: isDark
                          ? const Color(0xFFE2E8F0)
                          : const Color(0xFF334155),
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCallout(BuildContext context) {
    final type = block.extra?.toLowerCase() ?? 'info';
    Color borderColor;
    Color bgColor;
    IconData iconData;

    if (type == 'tip') {
      borderColor = const Color(0xFF10B981);
      bgColor = isDark
          ? const Color(0xFF064E3B).withOpacity(0.4)
          : const Color(0xFFD1FAE5);
      iconData = Icons.lightbulb_outline_rounded;
    } else if (type == 'warning') {
      borderColor = const Color(0xFFF59E0B);
      bgColor = isDark
          ? const Color(0xFF78350F).withOpacity(0.4)
          : const Color(0xFFFEF3C7);
      iconData = Icons.warning_amber_rounded;
    } else {
      borderColor = const Color(0xFF6366F1);
      bgColor = isDark
          ? const Color(0xFF1E1B4B).withOpacity(0.5)
          : const Color(0xFFEEF2FF);
      iconData = Icons.info_outline_rounded;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10.0),
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor.withOpacity(0.6), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(iconData, color: borderColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              block.content,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.45,
                color: isDark
                    ? const Color(0xFFF1F5F9)
                    : const Color(0xFF1E293B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageBlock(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12.0),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(
              block.content,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 180,
                color: isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFE2E8F0),
                alignment: Alignment.center,
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.image_not_supported_rounded,
                      size: 36,
                      color: Colors.grey,
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Image Preview Unavailable',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (block.caption != null && block.caption!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              block.caption!,
              style: TextStyle(
                fontSize: 12.5,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMathBlock(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF818CF8).withOpacity(0.4),
          width: 1.5,
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Math.tex(
            block.content,
            textStyle: TextStyle(
              fontSize: 20,
              color: isDark ? Colors.white : Colors.black87,
            ),
            onErrorFallback: (err) => Text(
              block.content,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 16,
                color: Colors.amber,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
