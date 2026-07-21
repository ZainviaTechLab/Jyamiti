import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

class LatexRichText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;

  const LatexRichText({
    super.key,
    required this.text,
    this.style,
    this.textAlign = TextAlign.start,
  });

  bool _isLatex(String val) {
    final clean = val.trim();
    return clean.contains('\\') || 
           clean.contains('^') || 
           clean.contains('_') || 
           clean.contains('{') || 
           clean.contains('}');
  }

  @override
  Widget build(BuildContext context) {
    String formattedText = text;
    if (_isLatex(formattedText) && !formattedText.contains('\$')) {
      formattedText = '\$$formattedText\$';
    }

    if (!formattedText.contains('\$')) {
      return Text(
        formattedText,
        style: style,
        textAlign: textAlign,
      );
    }

    // Convert double dollars $$ to single dollars $ for inline-style parsing
    final cleanText = formattedText.replaceAll('\$\$', '\$');
    final parts = cleanText.split('\$');
    final List<Widget> spans = [];

    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (i % 2 == 1) {
        // Odd index: Math LaTeX formula
        if (part.trim().isNotEmpty) {
          spans.add(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: Math.tex(
                part,
                textStyle: TextStyle(
                  color: style?.color ?? Colors.white,
                  fontSize: (style?.fontSize ?? 16) + 1,
                  fontWeight: style?.fontWeight,
                ),
                onErrorFallback: (err) => Text(
                  '\$$part\$',
                  style: style,
                ),
              ),
            ),
          );
        }
      } else {
        // Even index: Plain text
        if (part.isNotEmpty) {
          spans.add(
            Text(
              part,
              style: style,
            ),
          );
        }
      }
    }

    return Wrap(
      alignment: textAlign == TextAlign.center
          ? WrapAlignment.center
          : WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: spans,
    );
  }
}
