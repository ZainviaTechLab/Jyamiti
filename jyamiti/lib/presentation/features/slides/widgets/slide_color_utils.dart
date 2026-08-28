import 'package:flutter/material.dart';

/// Parses a hex color string into a Flutter [Color]. Accepts "6366F1"
/// (6-digit RGB, alpha assumed opaque), "FF6366F1" (8-digit ARGB), and
/// either with a leading '#'. Returns null for null/empty/unparseable
/// input -- callers treat null as "inherit the default", never as an
/// error, since these fields are optional overrides everywhere they're
/// used (see SlideBlock/SlideItem's own doc comments).
Color? parseHexColor(String? hex) {
  if (hex == null || hex.trim().isEmpty) return null;
  var cleaned = hex.trim().replaceFirst('#', '');
  if (cleaned.length == 6) cleaned = 'FF$cleaned';
  if (cleaned.length != 8) return null;
  final value = int.tryParse(cleaned, radix: 16);
  if (value == null) return null;
  return Color(value);
}

/// Converts a [Color] to an 8-digit "AARRGGBB" hex string (no '#') --
/// the same format [parseHexColor] reads back.
String colorToHex(Color color) {
  int channel(double c) => (c * 255).round().clamp(0, 255);
  final a = channel(color.a).toRadixString(16).padLeft(2, '0');
  final r = channel(color.r).toRadixString(16).padLeft(2, '0');
  final g = channel(color.g).toRadixString(16).padLeft(2, '0');
  final b = channel(color.b).toRadixString(16).padLeft(2, '0');
  return '$a$r$g$b'.toUpperCase();
}

/// A curated palette for the swatch picker below -- avoids pulling in a
/// whole color-picker package for what's fundamentally "pick one of a
/// reasonable set, or type an exact hex if you need one".
const List<Color> kSlideColorSwatches = [
  Color(0xFF0F172A), // slate-900
  Color(0xFF1E293B), // slate-800
  Color(0xFF334155), // slate-700
  Color(0xFF64748B), // slate-500
  Color(0xFFCBD5E1), // slate-300
  Color(0xFFF8FAFC), // slate-50
  Color(0xFFFFFFFF), // white
  Color(0xFF000000), // black
  Color(0xFF6366F1), // indigo-500
  Color(0xFF818CF8), // indigo-400
  Color(0xFF0EA5E9), // sky-500
  Color(0xFF38BDF8), // sky-400
  Color(0xFF10B981), // emerald-500
  Color(0xFF34D399), // emerald-400
  Color(0xFFF59E0B), // amber-500
  Color(0xFFFBBF24), // amber-400
  Color(0xFFEF4444), // red-500
  Color(0xFFF87171), // red-400
  Color(0xFFEC4899), // pink-500
  Color(0xFFA78BFA), // violet-400
  Color(0xFF14B8A6), // teal-500
  Color(0xFF78350F), // amber-900
  Color(0xFF1E1B4B), // indigo-950
  Color(0xFF064E3B), // emerald-900
];

/// A compact color picker: a swatch grid for quick picks, plus a hex text
/// field for an exact value, plus an optional "Clear" action that resets
/// the field to null (inherit the default). Used for slide backgrounds
/// and per-block background/text/border colors alike.
class SlideColorPickerField extends StatefulWidget {
  final String label;
  final String? initialHex;
  final ValueChanged<String?> onChanged;
  final bool allowClear;

  const SlideColorPickerField({
    super.key,
    required this.label,
    required this.initialHex,
    required this.onChanged,
    this.allowClear = true,
  });

  @override
  State<SlideColorPickerField> createState() => _SlideColorPickerFieldState();
}

class _SlideColorPickerFieldState extends State<SlideColorPickerField> {
  late final TextEditingController _hexController;

  @override
  void initState() {
    super.initState();
    _hexController = TextEditingController(text: widget.initialHex ?? '');
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _pick(Color color) {
    final hex = colorToHex(color);
    setState(() => _hexController.text = hex);
    widget.onChanged(hex);
  }

  void _clear() {
    setState(() => _hexController.text = '');
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final current = parseHexColor(_hexController.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              widget.label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const Spacer(),
            if (widget.allowClear && current != null)
              TextButton(
                onPressed: _clear,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 28),
                ),
                child: const Text('Clear', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: kSlideColorSwatches.map((c) {
            final bool isSelected = current != null &&
                colorToHex(current) == colorToHex(c);
            return GestureDetector(
              onTap: () => _pick(c),
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? const Color(0xFF6366F1) : Colors.grey.shade400,
                    width: isSelected ? 2.5 : 1,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _hexController,
          decoration: const InputDecoration(
            isDense: true,
            prefixText: '#',
            hintText: 'Hex, e.g. 6366F1',
            border: OutlineInputBorder(),
          ),
          onChanged: (val) {
            final parsed = parseHexColor(val);
            widget.onChanged(parsed != null ? colorToHex(parsed) : null);
          },
        ),
      ],
    );
  }
}
