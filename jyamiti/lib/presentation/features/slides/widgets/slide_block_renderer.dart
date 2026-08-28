import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../../../../domain/models/slide_deck_models.dart';
import '../../../widgets/inline_youtube_player.dart';
import 'slide_color_utils.dart';
import 'svg_style_inliner.dart';

class SlideBlockRenderer extends StatelessWidget {
  final SlideBlock block;
  final bool isDark;

  const SlideBlockRenderer({
    super.key,
    required this.block,
    this.isDark = true,
  });

  /// Resolves a text color for a text-dominant block: `block.textColor`
  /// when the author set one, otherwise whichever of the two theme
  /// defaults the block would have used anyway. Every text-heavy _build*
  /// method below (heading/subheading/paragraph/bulletList/callout) goes
  /// through this rather than hardcoding `isDark ? a : b` directly, so a
  /// custom foreground color actually takes effect. Code/math/svg/image/
  /// table blocks intentionally keep their own fixed color schemes --
  /// recoloring syntax-highlighted code or a math formula's accent color
  /// isn't generally what "custom text color" means for those.
  Color _textColorOr(Color darkDefault, Color lightDefault) {
    return parseHexColor(block.textColor) ??
        (isDark ? darkDefault : lightDefault);
  }

  /// The translucent fill for a `glass` frosted panel (banner/card/text,
  /// see each's doc comment) -- deliberately ignores whatever alpha
  /// [base] already carries and forces a fixed opacity instead, since a
  /// fully-opaque "glass" color would defeat the whole effect. Falls
  /// back to a neutral white/black tint (picked by [isDark]) when no
  /// background color was set at all, so turning Glass on by itself
  /// still produces a visible frosted panel. Blurring alone barely
  /// reads as "glass" over a smooth slide background/gradient -- there's
  /// no texture there for the blur to visibly act on -- so this alpha
  /// is deliberately higher than a typical translucent overlay, to give
  /// the panel a real presence even before _wrapGlass's shadow/sheen.
  Color _glassTint(Color? base) {
    final Color source = base ?? (isDark ? Colors.white : Colors.black);
    return source.withValues(alpha: isDark ? 0.22 : 0.16);
  }

  /// The frosted panel's own edge highlight -- a bright, fairly opaque
  /// rim rather than a faint one, since that crisp edge (a "glass lip
  /// catching light") is one of the main things that reads as glass
  /// rather than just a translucent box, especially when the blur
  /// behind it has little to actually blur.
  Color get _glassBorderColor => Colors.white.withValues(alpha: 0.55);

  /// Wraps [child] with everything that makes a translucent box actually
  /// read as frosted glass rather than just "a see-through box": a
  /// backdrop blur of whatever renders behind it, a soft drop shadow for
  /// depth (applied outside the clip, so it isn't cut off by it), and a
  /// diagonal sheen highlight -- that last one matters most when the
  /// slide behind the panel is a smooth gradient/solid color, since
  /// blurring smoothness looks nearly identical to not blurring it at
  /// all; the sheen is what still reads as "glass" in that case. [child]
  /// must already be exactly the shape being frosted (its own decoration
  /// should use [borderRadius]) since BackdropFilter blurs everything
  /// within the ClipRRect's bounds.
  Widget _wrapGlass(Widget child, {required BorderRadius borderRadius}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.38 : 0.14),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          // foregroundDecoration paints the sheen directly on top of
          // [child] without affecting layout at all -- a Stack was
          // tried here first, but Stack gives its non-positioned
          // children (child) loose constraints and pins them to
          // top-left, whereas a Positioned.fill sibling still fills
          // the Stack's own (possibly wider, e.g. a card's boxed 85%-
          // width FractionallySizedBox forcing this whole wrapper's
          // width) resolved size -- the result was a correctly-sized
          // bordered box hugging one corner with the blur/shadow/sheen
          // still spanning the full forced width around it, a visible
          // "ghost" smear past the box's own edge. foregroundDecoration
          // has no such quirk: this Container just defers its size to
          // child exactly as if it wasn't here.
          child: Container(
            foregroundDecoration: BoxDecoration(
              borderRadius: borderRadius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: const [0.0, 0.5],
                colors: [
                  Colors.white.withValues(alpha: isDark ? 0.16 : 0.24),
                  Colors.white.withValues(alpha: 0.0),
                ],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Banner, card, and text all fully own their own background/text/
    // outline rendering already (banner: its whole layout, see
    // _buildBannerBlock's doc comment; card: _buildCardBlock/
    // _buildSingleCard's own decoration; text: _buildTextBlock's own
    // decoration) -- routing any of them through the generic wrapper
    // below too would double them up: their own colored/bordered box,
    // wrapped in a second outer box using the identical color/border,
    // since all three read directly from block.backgroundColor/
    // textColor/borderColor.
    if (block.type == SlideBlockType.banner) return _buildBannerBlock(context);
    if (block.type == SlideBlockType.card) return _buildCardBlock(context);
    if (block.type == SlideBlockType.text) return _buildTextBlock(context);

    final Widget content = _buildContent(context);
    final Color? bg = parseHexColor(block.backgroundColor);
    final Color? border = parseHexColor(block.borderColor);
    if (bg == null && border == null) return content;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: border != null
            ? Border.all(
                color: border,
                width: block.borderWidth > 0 ? block.borderWidth : 1.5,
              )
            : null,
      ),
      child: content,
    );
  }

  Widget _buildContent(BuildContext context) {
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
      case SlideBlockType.table:
        return _buildTableBlock(context);
      case SlideBlockType.video:
        return _buildVideoBlock(context);
      case SlideBlockType.card:
        // Never actually reached -- build() special-cases card before
        // this switch runs (see the comment there). Listed anyway so
        // this switch stays exhaustive without a `default` swallowing a
        // real future omission for any other type.
        return _buildCardBlock(context);
      case SlideBlockType.columns:
        return _buildColumnsBlock(context);
      case SlideBlockType.banner:
        // Never actually reached -- build() special-cases banner before
        // this switch runs. Listed anyway so this switch stays
        // exhaustive without a `default` swallowing a real future
        // omission for any other type.
        return _buildBannerBlock(context);
      case SlideBlockType.text:
        // Never actually reached -- build() special-cases text before
        // this switch runs, same reason as banner/card above.
        return _buildTextBlock(context);
    }
  }

  Widget _buildHeading(BuildContext context) {
    final Color? custom = parseHexColor(block.textColor);
    // A custom color overrides the default gradient treatment entirely --
    // a flat ShaderMask-free Text with that exact color, rather than
    // tinting the gradient (which would just look muddy).
    if (custom != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12.0, top: 8.0),
        child: Text(
          block.content,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: custom,
            height: 1.25,
            letterSpacing: -0.5,
          ),
        ),
      );
    }

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
          color: _textColorOr(Colors.white, const Color(0xFF1E293B)),
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
            color: _textColorOr(const Color(0xFFCBD5E1), const Color(0xFF334155)),
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
              color: _textColorOr(const Color(0xFFCBD5E1), const Color(0xFF334155)),
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
            color: _textColorOr(const Color(0xFFCBD5E1), const Color(0xFF334155)),
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
                      color: _textColorOr(
                          const Color(0xFFE2E8F0), const Color(0xFF334155)),
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
                color: _textColorOr(
                    const Color(0xFFF1F5F9), const Color(0xFF1E293B)),
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

  /// `block.content` is a JSON-encoded {"headers": [...], "rows": [[...],
  /// ...]} object -- consistent with this model's existing convention of
  /// `content` being a flexible string whose format depends on `type`
  /// (bulletList newline-joins its items into `content`, table
  /// JSON-encodes a 2D grid into it, rather than adding a whole new field
  /// to SlideBlock just for this one type).
  Widget _buildTableBlock(BuildContext context) {
    List<String> headers = [];
    List<List<String>> rows = [];
    try {
      final data = json.decode(block.content) as Map<String, dynamic>;
      headers = (data['headers'] as List? ?? [])
          .map((e) => e.toString())
          .toList();
      rows = (data['rows'] as List? ?? [])
          .map((r) => (r as List).map((c) => c.toString()).toList())
          .toList();
    } catch (_) {
      // Malformed/empty table data -- render nothing rather than crash.
    }

    final Color gridColor =
        isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final Color headerBg =
        isDark ? const Color(0xFF1E293B) : const Color(0xFFEEF2FF);
    final Color textColor =
        _textColorOr(const Color(0xFFE2E8F0), const Color(0xFF334155));

    if (headers.isEmpty && rows.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 10.0),
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          border: Border.all(color: gridColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Empty table',
          style: TextStyle(color: textColor, fontStyle: FontStyle.italic),
        ),
      );
    }

    Widget cell(String text, {bool isHeader = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Text(
            text,
            style: TextStyle(
              color: textColor,
              fontSize: 13.5,
              fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: gridColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder(
            horizontalInside: BorderSide(color: gridColor),
            verticalInside: BorderSide(color: gridColor),
          ),
          children: [
            if (headers.isNotEmpty)
              TableRow(
                decoration: BoxDecoration(color: headerBg),
                children:
                    headers.map((h) => cell(h, isHeader: true)).toList(),
              ),
            ...rows.map(
              (r) => TableRow(children: r.map((c) => cell(c)).toList()),
            ),
          ],
        ),
      ),
    );
  }

  /// `block.content` is a YouTube URL or bare video id -- reuses the
  /// app's existing InlineYoutubePlayer (already used elsewhere, e.g. the
  /// syllabus explorer) rather than embedding a player from scratch.
  Widget _buildVideoBlock(BuildContext context) {
    final String raw = block.content.trim();
    final String videoId =
        YoutubePlayerController.convertUrlToId(raw) ?? raw;

    if (videoId.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 10.0),
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          'No video URL set',
          style: TextStyle(
            color: _textColorOr(
                const Color(0xFF94A3B8), const Color(0xFF64748B)),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12.0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: InlineYoutubePlayer(videoId: videoId, videoUrl: raw),
      ),
    );
  }

  /// Builds a native styled Card or Framed Box block.
  /// Supports inline LaTeX math, custom border/background colors, and width modes.
  Widget _buildCardBlock(BuildContext context) {
    // Check if content is a JSON list of cards
    if (block.content.trim().startsWith('[') &&
        block.content.trim().endsWith(']')) {
      try {
        final decoded = json.decode(block.content) as List;
        if (decoded.isNotEmpty && decoded.first is Map) {
          return _buildCardsList(
              context, decoded.cast<Map<String, dynamic>>());
        }
      } catch (_) {}
    }

    return _buildSingleCard(
      context,
      title: block.caption,
      content: block.content,
      borderColorStr: block.borderColor,
      borderWidth: block.borderWidth > 0 ? block.borderWidth : 2.0,
      bgColorStr: block.backgroundColor,
      textColorStr: block.textColor,
      extra: block.extra,
      glass: block.glass,
      horizontalAlign: block.horizontalAlign,
    );
  }

  Widget _buildSingleCard(
    BuildContext context, {
    String? title,
    required String content,
    String? borderColorStr,
    double borderWidth = 2.0,
    String? bgColorStr,
    String? textColorStr,
    String? extra,
    bool glass = false,
    String? horizontalAlign,
  }) {
    final TextAlign contentAlign = switch (horizontalAlign) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      'justify' => TextAlign.justify,
      _ => TextAlign.left,
    };
    final CrossAxisAlignment cardCrossAlign = switch (horizontalAlign) {
      'center' => CrossAxisAlignment.center,
      'right' => CrossAxisAlignment.end,
      'justify' => CrossAxisAlignment.stretch,
      _ => CrossAxisAlignment.start,
    };
    final Color? explicitBorder = parseHexColor(borderColorStr);
    final Color defaultAccent =
        isDark ? const Color(0xFF22C55E) : const Color(0xFF16A34A);
    // The box border can go translucent under glass (that's the whole
    // point), but the title text below reuses this same accent color --
    // keep a separate, always-opaque version for that so an unset
    // border under glass doesn't also wash out the title to near
    // invisibility.
    final Color borderColor = glass
        ? (explicitBorder ?? _glassBorderColor)
        : (explicitBorder ?? defaultAccent);
    final Color titleAccent =
        explicitBorder ?? (glass ? Colors.white : defaultAccent);
    final Color bgColor = glass
        ? _glassTint(parseHexColor(bgColorStr))
        : (parseHexColor(bgColorStr) ??
            (isDark ? const Color(0xFF0B2240) : const Color(0xFFF1F5F9)));
    final Color textColor = parseHexColor(textColorStr) ??
        (isDark || glass ? const Color(0xFFFFFFFF) : const Color(0xFF0F172A));

    final mode = (extra ?? 'boxed').toLowerCase().trim();
    double? widthFactor;
    if (mode == 'compact' || mode == '75%') {
      widthFactor = 0.75;
    } else if (mode == 'small' || mode == '50%') {
      widthFactor = 0.50;
    } else if (mode == 'full') {
      widthFactor = null;
    } else if (mode.endsWith('%')) {
      final parsed = double.tryParse(mode.replaceAll('%', '').trim());
      if (parsed != null && parsed > 0 && parsed <= 100) {
        widthFactor = parsed / 100.0;
      }
    } else {
      // Default boxed card width
      widthFactor = 0.85;
    }

    final BorderRadius cardRadius = BorderRadius.circular(16);
    Widget cardWidget = Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: cardRadius,
        border: Border.all(color: borderColor, width: borderWidth),
        // A drop shadow would get clipped hard at the card's own edge
        // by the ClipRRect glass wrapping needs below, reading as a
        // stray line rather than a soft shadow -- skip it for glass,
        // the blur+translucency already reads as "lifted" on its own.
        boxShadow: glass
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: cardCrossAlign,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null && title.trim().isNotEmpty) ...[
            Text(
              title.trim(),
              textAlign: contentAlign,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: titleAccent,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 10),
          ],
          _buildRichCardContent(content, textColor, textAlign: contentAlign),
        ],
      ),
    );
    if (glass) cardWidget = _wrapGlass(cardWidget, borderRadius: cardRadius);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 10.0),
      alignment: Alignment.center,
      child: widthFactor != null
          ? FractionallySizedBox(
              widthFactor: widthFactor,
              child: cardWidget,
            )
          : cardWidget,
    );
  }

  Widget _buildCardsList(
      BuildContext context, List<Map<String, dynamic>> cardItems) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12.0),
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final isWide = constraints.maxWidth > 650;
          final cardWidgets = cardItems.map((item) {
            final title =
                item['title']?.toString() ?? item['caption']?.toString();
            final content = item['content']?.toString() ??
                item['text']?.toString() ??
                item['math']?.toString() ??
                '';
            final bColor = parseHexColor(item['borderColor']?.toString()) ??
                (isDark ? const Color(0xFFF472B6) : const Color(0xFFDB2777));
            final bg = parseHexColor(item['backgroundColor']?.toString()) ??
                (isDark ? const Color(0xFF0B2240) : const Color(0xFFF1F5F9));
            final txtColor = parseHexColor(item['textColor']?.toString()) ??
                (isDark ? Colors.white : const Color(0xFF0F172A));

            return Container(
              margin: const EdgeInsets.all(6.0),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: bColor, width: 2.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title != null && title.trim().isNotEmpty) ...[
                    Text(
                      title.trim(),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: bColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  _buildRichCardContent(content, txtColor),
                ],
              ),
            );
          }).toList();

          if (isWide && cardItems.length <= 4) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: cardWidgets.map((w) => Expanded(child: w)).toList(),
            );
          } else {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: cardWidgets,
            );
          }
        },
      ),
    );
  }

  Widget _buildRichCardContent(
    String text,
    Color defaultColor, {
    TextAlign textAlign = TextAlign.left,
  }) {
    final mathRegex = RegExp(r'(\$\$[\s\S]*?\$\$|\$[^\$\n]+?\$)');
    final lines = text.split('\n');

    return Column(
      // .start (the plain-left default) lets each line shrink-wrap to
      // its own width, same as elsewhere in this file -- but that means
      // a non-left textAlign would have no extra room to align within,
      // so anything else here needs .stretch to actually give textAlign
      // something to work against (see _buildTextBlock's near-identical
      // fix for the standalone text block).
      crossAxisAlignment: textAlign == TextAlign.left
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: lines.map((line) {
        if (!mathRegex.hasMatch(line)) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.5),
            child: Text(
              line,
              textAlign: textAlign,
              style: TextStyle(
                fontSize: 17,
                height: 1.4,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                color: defaultColor,
              ),
            ),
          );
        }

        final spans = <InlineSpan>[];
        int lastEnd = 0;

        for (final match in mathRegex.allMatches(line)) {
          if (match.start > lastEnd) {
            spans.add(
              TextSpan(
                text: line.substring(lastEnd, match.start),
                style: TextStyle(
                  fontSize: 17,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  color: defaultColor,
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
                padding: const EdgeInsets.symmetric(horizontal: 2.0),
                child: Math.tex(
                  cleanTex,
                  textStyle: TextStyle(
                    fontSize: 18,
                    color: isDark
                        ? const Color(0xFF38BDF8)
                        : const Color(0xFF4338CA),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );

          lastEnd = match.end;
        }

        if (lastEnd < line.length) {
          spans.add(
            TextSpan(
              text: line.substring(lastEnd),
              style: TextStyle(
                fontSize: 17,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                color: defaultColor,
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.5),
          child: SelectableText.rich(
            TextSpan(children: spans),
            textAlign: textAlign,
          ),
        );
      }).toList(),
    );
  }

  /// `block.content` is JSON-encoded {"columns": [[blockMap, blockMap,
  /// ...], [...], ...]} -- one inner array of block maps per column, each
  /// parsed back into real SlideBlocks and rendered with a nested
  /// SlideBlockRenderer. This is what actually makes "mixed content per
  /// column" possible: a column isn't restricted to one content type --
  /// it can hold any mix of images, cards, text, tables, whatever, since
  /// each cell is a full block, not a plain string like a table cell.
  /// See ColumnsBlockEditorScreen for how this content actually gets
  /// built/edited.
  Widget _buildColumnsBlock(BuildContext context) {
    List<List<SlideBlock>> columns = [];
    try {
      final data = json.decode(block.content) as Map<String, dynamic>;
      final rawColumns = data['columns'] as List? ?? [];
      columns = rawColumns.map((col) {
        return (col as List)
            .map((b) => SlideBlock.fromMap(b as Map<String, dynamic>))
            .toList();
      }).toList();
    } catch (_) {
      // Malformed/empty columns data -- render nothing rather than crash.
    }

    if (columns.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 10.0),
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Empty columns block',
          style: TextStyle(
            color: _textColorOr(
                const Color(0xFF94A3B8), const Color(0xFF64748B)),
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    Widget columnContent(List<SlideBlock> blocks) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: blocks
              .map((b) => SlideBlockRenderer(block: b, isDark: isDark))
              .toList(),
        );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10.0),
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          // Stacks vertically on narrow panels (e.g. a column nested
          // inside another column's editor preview) rather than
          // squeezing every column into an unusable sliver.
          if (constraints.maxWidth < 480) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final col in columns)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: columnContent(col),
                  ),
              ],
            );
          }
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < columns.length; i++) ...[
                  if (i > 0) const SizedBox(width: 20),
                  Expanded(child: columnContent(columns[i])),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  /// A full-width colored bar with a title -- e.g. a section divider
  /// between groups of content on a slide. Handles its own background/
  /// text/border AND the newer layout fields (padding/marginVertical/
  /// fontSize/horizontalAlign/verticalAlign/minHeight) directly, rather
  /// than going through the generic bg/border wrapper every other block
  /// shares, since a banner's whole purpose IS that styling -- routing it
  /// through the generic wrapper too would double up the box.
  ///
  /// Defaults (when a field is unset -- see
  /// slide_block_defaults.dart's applyBannerDefaults, which is what a
  /// freshly-added banner actually gets): amber background, black text,
  /// 16px padding, 12px vertical margin, 20px font, centered both ways.
  Widget _buildBannerBlock(BuildContext context) {
    final Color? explicitBg = parseHexColor(block.backgroundColor);
    final Color bg = block.glass
        ? _glassTint(explicitBg)
        : (explicitBg ?? const Color(0xFFF59E0B));
    final Color? explicitBorder = parseHexColor(block.borderColor);
    final Color? border = block.glass
        ? (explicitBorder ?? _glassBorderColor)
        : explicitBorder;
    // A flat black default (banner's non-glass default) reads poorly on
    // a blurred, arbitrary slide background -- glass without an
    // explicit text color falls back to white instead.
    final Color textColor = parseHexColor(block.textColor) ??
        (block.glass ? Colors.white : const Color(0xFF000000));
    final double padding = block.padding ?? 16;
    final double marginV = block.marginVertical ?? 12;
    final double fontSize = block.fontSize ?? 20;

    final TextAlign textAlign = switch (block.horizontalAlign) {
      'left' => TextAlign.left,
      'right' => TextAlign.right,
      _ => TextAlign.center,
    };
    final Alignment boxAlignment = switch ((
      block.horizontalAlign,
      block.verticalAlign
    )) {
      ('left', 'top') => Alignment.topLeft,
      ('left', 'bottom') => Alignment.bottomLeft,
      ('left', _) => Alignment.centerLeft,
      ('right', 'top') => Alignment.topRight,
      ('right', 'bottom') => Alignment.bottomRight,
      ('right', _) => Alignment.centerRight,
      (_, 'top') => Alignment.topCenter,
      (_, 'bottom') => Alignment.bottomCenter,
      (_, _) => Alignment.center,
    };

    final BorderRadius radius = BorderRadius.circular(14);
    Widget box = Container(
      width: double.infinity,
      padding: EdgeInsets.all(padding),
      constraints: block.minHeight != null
          ? BoxConstraints(minHeight: block.minHeight!)
          : null,
      alignment: boxAlignment,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        border: border != null
            ? Border.all(
                color: border,
                width: block.borderWidth > 0 ? block.borderWidth : 1.5,
              )
            : null,
      ),
      child: Text(
        block.content,
        textAlign: textAlign,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
    if (block.glass) box = _wrapGlass(box, borderRadius: radius);

    return Container(
      margin: EdgeInsets.symmetric(vertical: marginV),
      child: box,
    );
  }

  /// A freeform styled line/paragraph of text -- unlike banner (always a
  /// centered colored bar) or card (always boxed with a border), `text`
  /// has no fixed shape of its own: background/border are optional (null
  /// means "just text, no box"), and bold/italic/underline/strikethrough
  /// combine freely via TextDecoration.combine. Reuses the same
  /// backgroundColor/textColor/borderColor/borderWidth/fontSize/
  /// horizontalAlign fields banner and card already read -- see this
  /// widget's `build()` for why text is excluded from the generic
  /// wrapper despite reading those same fields itself.
  Widget _buildTextBlock(BuildContext context) {
    final Color? explicitBg = parseHexColor(block.backgroundColor);
    final Color? explicitBorder = parseHexColor(block.borderColor);
    // Glass implies a box even if the author never touched Background/
    // Outline -- it's effectively a background choice of its own, so
    // turning it on alone should still produce a visible frosted panel.
    final Color? bg = block.glass ? _glassTint(explicitBg) : explicitBg;
    final Color? border = block.glass
        ? (explicitBorder ?? _glassBorderColor)
        : explicitBorder;
    final Color textColor =
        _textColorOr(const Color(0xFFCBD5E1), const Color(0xFF334155));
    final double fontSize = block.fontSize ?? 15.5;

    final TextAlign textAlign = switch (block.horizontalAlign) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      'justify' => TextAlign.justify,
      _ => TextAlign.left,
    };

    final decorations = <TextDecoration>[
      if (block.underline) TextDecoration.underline,
      if (block.strikethrough) TextDecoration.lineThrough,
    ];

    final TextStyle baseStyle = TextStyle(
      fontSize: fontSize,
      height: 1.5,
      color: textColor,
      fontWeight: block.bold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: block.italic ? FontStyle.italic : FontStyle.normal,
      decoration: decorations.isEmpty
          ? TextDecoration.none
          : TextDecoration.combine(decorations),
    );
    // GoogleFonts.getFont resolves any family name it recognizes and
    // merges it into baseStyle (keeping color/weight/decoration/etc
    // intact) -- a name it doesn't recognize just falls back to the
    // theme's default font rather than throwing, so a hand-written
    // JSON import with a typo'd/unsupported family degrades quietly
    // instead of breaking the slide.
    final TextStyle textStyle = block.fontFamily != null
        ? GoogleFonts.getFont(block.fontFamily!, textStyle: baseStyle)
        : baseStyle;

    final text = Text(
      block.content,
      textAlign: textAlign,
      style: textStyle,
    );

    final bool boxed = bg != null || border != null || block.glass;
    final BorderRadius radius = BorderRadius.circular(14);

    // A box that hugs the text's own width, for when the box itself
    // (not just the text inside it) should look like a tag/chip rather
    // than a full-width bar. `fitContent` only means anything when
    // there's actually a box to shrink -- an unboxed block always uses
    // the full-width path below regardless of this flag.
    if (boxed && block.fitContent) {
      final Alignment boxAlignment = switch (block.horizontalAlign) {
        'center' => Alignment.center,
        'right' => Alignment.centerRight,
        _ => Alignment.centerLeft,
      };
      Widget box = Container(
        padding: const EdgeInsets.all(14.0),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: radius,
          border: border != null
              ? Border.all(
                  color: border,
                  width: block.borderWidth > 0 ? block.borderWidth : 1.5,
                )
              : null,
        ),
        child: text,
      );
      if (block.glass) box = _wrapGlass(box, borderRadius: radius);
      return Padding(
        padding: const EdgeInsets.only(bottom: 12.0),
        child: Align(alignment: boxAlignment, child: box),
      );
    }

    // Always a full-width box, even when unboxed (no bg/border/glass) --
    // a plain Padding here would shrink-wrap to the text's own intrinsic
    // width, leaving `textAlign` nothing wider than the text itself to
    // align within, so center/right/justify would silently render as
    // left-aligned. width: double.infinity is what actually gives
    // textAlign room to work (same technique _buildBannerBlock uses).
    Widget box = Container(
      width: double.infinity,
      padding: boxed ? const EdgeInsets.all(14.0) : EdgeInsets.zero,
      decoration: boxed
          ? BoxDecoration(
              color: bg,
              borderRadius: radius,
              border: border != null
                  ? Border.all(
                      color: border,
                      width: block.borderWidth > 0 ? block.borderWidth : 1.5,
                    )
                  : null,
            )
          : null,
      child: text,
    );
    if (block.glass) box = _wrapGlass(box, borderRadius: radius);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: box,
    );
  }
}
