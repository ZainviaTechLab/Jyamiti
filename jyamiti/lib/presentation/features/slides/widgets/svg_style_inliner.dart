class SvgDimensions {
  final double? width;
  final double? height;
  final double aspectRatio;

  const SvgDimensions({
    this.width,
    this.height,
    this.aspectRatio = 16 / 9,
  });
}

class SvgStyleInliner {
  /// Converts internal CSS `<style>` rules and `<svg style="...">` background properties
  /// into direct SVG element presentation attributes.
  ///
  /// This is necessary because `flutter_svg` does not evaluate CSS stylesheet
  /// classes (.line, .number, etc.) or `<style>` blocks.
  static String process(String rawSvg) {
    if (rawSvg.trim().isEmpty) return rawSvg;

    try {
      String svg = rawSvg;

      // 1. Extract and process background-color from root <svg> style attribute if present
      svg = _injectBackgroundRectIfNeeded(svg);

      // 2. If there are no <style> blocks, return
      final styleRegex = RegExp(
        r'<style[^>]*>([\s\S]*?)<\/style>',
        caseSensitive: false,
      );

      final styleMatches = styleRegex.allMatches(svg);
      if (styleMatches.isEmpty) {
        return svg;
      }

      // Collect all CSS rules
      final Map<String, Map<String, String>> tagRules = {};
      final Map<String, Map<String, String>> classRules = {};

      for (final match in styleMatches) {
        final cssContent = match.group(1) ?? '';
        _parseCssRules(cssContent, tagRules, classRules);
      }

      // 3. Remove all <style>...</style> blocks to eliminate "unhandled element <style/>" warnings
      svg = svg.replaceAll(styleRegex, '');

      // 4. In-line CSS styles directly onto XML elements
      // Regex matching any opening XML tag: <tagName ... > or <tagName ... />
      final elementRegex = RegExp(
        r'<([a-zA-Z0-9]+)\b([^>]*?)(\/?)>',
        multiLine: true,
      );

      svg = svg.replaceAllMapped(elementRegex, (match) {
        final tagName = match.group(1)!.toLowerCase();
        final existingAttrs = match.group(2) ?? '';
        final isSelfClosing = match.group(3) == '/';

        // Ignore container/meta tags that shouldn't receive styles
        if (tagName == 'svg' ||
            tagName == 'g' ||
            tagName == 'defs' ||
            tagName == 'clippath' ||
            tagName == 'mask') {
          return match.group(0)!;
        }

        // Collect attributes to apply
        final Map<String, String> mergedProps = {};

        // A. Tag-level default styles (e.g. text { fill: #ffffff })
        if (tagRules.containsKey(tagName)) {
          mergedProps.addAll(tagRules[tagName]!);
        }

        // B. Class-level styles (e.g. class="line" or class='number operator')
        final classAttrMatch = RegExp(
          r'''\bclass=(["'])(.*?)\1''',
          caseSensitive: false,
        ).firstMatch(existingAttrs);

        if (classAttrMatch != null) {
          final classList = classAttrMatch
              .group(2)!
              .split(RegExp(r'\s+'))
              .where((c) => c.isNotEmpty);
          for (final cls in classList) {
            if (classRules.containsKey(cls)) {
              mergedProps.addAll(classRules[cls]!);
            }
          }
        }

        if (mergedProps.isEmpty) {
          return match.group(0)!;
        }

        // C. Build attribute string, preserving any explicitly defined attributes on element
        final sb = StringBuffer();
        mergedProps.forEach((propKey, propVal) {
          // Check if attribute already exists on element (e.g. stroke="...")
          final attrPattern = RegExp(
            '''\\b${RegExp.escape(propKey)}\\s*=\\s*(["'])''',
            caseSensitive: false,
          );
          if (!attrPattern.hasMatch(existingAttrs)) {
            sb.write(" $propKey='$propVal'");
          }
        });

        final addedAttrs = sb.toString();
        if (isSelfClosing) {
          return '<$tagName$existingAttrs$addedAttrs />';
        } else {
          return '<$tagName$existingAttrs$addedAttrs>';
        }
      });

      return svg;
    } catch (e) {
      return rawSvg;
    }
  }

  /// Injects a background `<rect>` if the `<svg>` element defines a CSS background color.
  static String _injectBackgroundRectIfNeeded(String svg) {
    final svgTagMatch = RegExp(
      r'<svg\b([^>]*?)>',
      caseSensitive: false,
    ).firstMatch(svg);

    if (svgTagMatch == null) return svg;

    final svgAttrs = svgTagMatch.group(1) ?? '';
    String? bgColor;

    // Check style="background-color:#0b2240; ..." or style='background: ...'
    final styleAttrMatch = RegExp(
      r'''style=(["'])(.*?)\1''',
      caseSensitive: false,
    ).firstMatch(svgAttrs);

    if (styleAttrMatch != null) {
      final styleVal = styleAttrMatch.group(2)!;
      final bgMatch = RegExp(
        r'background(?:-color)?\s*:\s*([^;]+)',
        caseSensitive: false,
      ).firstMatch(styleVal);
      if (bgMatch != null) {
        bgColor = bgMatch.group(1)!.trim();
      }
    }

    if (bgColor != null &&
        bgColor.isNotEmpty &&
        !svg.contains('<rect width="100%"') &&
        !svg.contains("<rect width='100%'")) {
      final insertPos = svgTagMatch.end;
      final bgRect =
          "\n<rect width='100%' height='100%' fill='$bgColor' rx='16' ry='16' />";
      return svg.substring(0, insertPos) + bgRect + svg.substring(insertPos);
    }

    return svg;
  }

  /// Extracts dimensions and aspect ratio from SVG viewBox or width/height attributes.
  static SvgDimensions extractDimensions(String svg) {
    try {
      final viewBoxMatch = RegExp(
        r'''viewBox=(["'])\s*([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s*\1''',
        caseSensitive: false,
      ).firstMatch(svg);

      if (viewBoxMatch != null) {
        final w = double.tryParse(viewBoxMatch.group(4) ?? '');
        final h = double.tryParse(viewBoxMatch.group(5) ?? '');
        if (w != null && h != null && h > 0 && w > 0) {
          return SvgDimensions(width: w, height: h, aspectRatio: w / h);
        }
      }

      final wMatch = RegExp(
        r'''\bwidth=(["'])([\d.]+)\1''',
        caseSensitive: false,
      ).firstMatch(svg);
      final hMatch = RegExp(
        r'''\bheight=(["'])([\d.]+)\1''',
        caseSensitive: false,
      ).firstMatch(svg);
      if (wMatch != null && hMatch != null) {
        final w = double.tryParse(wMatch.group(2) ?? '');
        final h = double.tryParse(hMatch.group(2) ?? '');
        if (w != null && h != null && h > 0 && w > 0) {
          return SvgDimensions(width: w, height: h, aspectRatio: w / h);
        }
      }
    } catch (_) {}
    return const SvgDimensions(aspectRatio: 16 / 9);
  }

  /// Extracts aspect ratio (width / height) from SVG viewBox or width/height.
  /// Defaults to 16 / 9 (1.778).
  static double extractAspectRatio(String svg) {
    return extractDimensions(svg).aspectRatio;
  }

  /// Parses CSS text into tag rules and class rules.
  static void _parseCssRules(
    String css,
    Map<String, Map<String, String>> tagRules,
    Map<String, Map<String, String>> classRules,
  ) {
    // Matches: selector { key: val; key2: val2; }
    final ruleRegex = RegExp(r'([^{]+)\{([^}]+)\}');

    for (final match in ruleRegex.allMatches(css)) {
      final rawSelectors = match.group(1) ?? '';
      final rawBody = match.group(2) ?? '';

      final Map<String, String> declarations = {};
      final declPairs = rawBody.split(';');
      for (final pair in declPairs) {
        final colonIdx = pair.indexOf(':');
        if (colonIdx > 0) {
          final prop = pair.substring(0, colonIdx).trim().toLowerCase();
          var val = pair.substring(colonIdx + 1).trim();

          // Strip 'px' unit for SVG numerical presentation attributes
          if (prop == 'font-size' ||
              prop == 'stroke-width' ||
              prop == 'stroke-dasharray' ||
              prop == 'letter-spacing') {
            val = val.replaceAll('px', '');
          }

          if (prop.isNotEmpty && val.isNotEmpty) {
            declarations[prop] = val;
          }
        }
      }

      if (declarations.isEmpty) continue;

      final selectors = rawSelectors.split(',');
      for (var sel in selectors) {
        sel = sel.trim();
        if (sel.isEmpty) continue;

        if (sel.startsWith('.')) {
          final className = sel.substring(1).trim();
          classRules.putIfAbsent(className, () => {}).addAll(declarations);
        } else {
          final tagName = sel.toLowerCase();
          tagRules.putIfAbsent(tagName, () => {}).addAll(declarations);
        }
      }
    }
  }
}
