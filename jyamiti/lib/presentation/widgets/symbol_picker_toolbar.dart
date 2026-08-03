import 'package:flutter/material.dart';
import 'package:jyamiti/providers/theme_provider.dart';

/// A rich categorized collection of mathematical, scientific, geometric, and LaTeX symbols.
class MathSymbolCategory {
  final String title;
  final IconData icon;
  final List<String> symbols;

  const MathSymbolCategory({
    required this.title,
    required this.icon,
    required this.symbols,
  });
}

class MathSymbolsData {
  static const List<String> quickSymbols = [
    'π',
    'θ',
    '√',
    '±',
    '≠',
    '≤',
    '≥',
    '°',
    '²',
    '³',
    '½',
    '∠',
    '△',
    'α',
    'β',
    '→',
    '∞',
    '∫',
    '∑',
    '\\frac{a}{b}',
  ];

  static const List<MathSymbolCategory> categories = [
    MathSymbolCategory(
      title: 'Operators & Basic',
      icon: Icons.calculate_outlined,
      symbols: [
        '+',
        '−',
        '×',
        '÷',
        '=',
        '≠',
        '±',
        '∓',
        '≈',
        '≡',
        '≤',
        '≥',
        '∞',
        '%',
        '‰',
        '√',
        '∛',
        '∜',
      ],
    ),
    MathSymbolCategory(
      title: 'Geometry & Units',
      icon: Icons.square_foot_outlined,
      symbols: [
        '∠',
        '△',
        '□',
        '○',
        '∥',
        '⊥',
        '°',
        'π',
        'r',
        'r²',
        'cm',
        'cm²',
        'm²',
        'm³',
        'km',
        'kg',
        'g',
        'N',
        'J',
      ],
    ),
    MathSymbolCategory(
      title: 'Greek Letters',
      icon: Icons.font_download_outlined,
      symbols: [
        'α',
        'β',
        'γ',
        'δ',
        'ε',
        'ζ',
        'η',
        'θ',
        'κ',
        'λ',
        'μ',
        'ν',
        'ξ',
        'π',
        'ρ',
        'σ',
        'τ',
        'φ',
        'χ',
        'ψ',
        'ω',
        'Δ',
        'Σ',
        'Ω',
        'Φ',
        'Ψ',
      ],
    ),
    MathSymbolCategory(
      title: 'Sub / Superscripts',
      icon: Icons.superscript_outlined,
      symbols: [
        '²',
        '³',
        'ⁿ',
        '⁺',
        '⁻',
        '₀',
        '₁',
        '₂',
        '₃',
        '₄',
        '₅',
        '₆',
        '₇',
        '₈',
        '₉',
        'ₓ',
        '½',
        '⅓',
        '⅔',
        '¼',
        '¾',
        '⅕',
      ],
    ),
    MathSymbolCategory(
      title: 'Arrows & Logic',
      icon: Icons.east_outlined,
      symbols: [
        '→',
        '⇒',
        '↔',
        '⇔',
        '↑',
        '↓',
        '∈',
        '∉',
        '⊂',
        '⊆',
        '∪',
        '∩',
        '∴',
        '∵',
        '∀',
        '∃',
        '¬',
        '∧',
        '∨',
      ],
    ),
    MathSymbolCategory(
      title: 'LaTeX Code',
      icon: Icons.code_outlined,
      symbols: [
        '\\frac{a}{b}',
        'x^{2}',
        'x_{n}',
        '\\sqrt{x}',
        '\\alpha',
        '\\beta',
        '\\theta',
        '\\pi',
        '\\pm',
        '\\le',
        '\\ge',
        '\\neq',
        '\\times',
        '\\div',
        '\\int_{a}^{b}',
        '\\sum_{i=1}^{n}',
        '\\lim_{x \\to 0}',
      ],
    ),
  ];

  /// Inserts [symbol] at the current cursor position of [controller].
  static void insertSymbol(
    TextEditingController controller,
    String symbol, {
    FocusNode? focusNode,
  }) {
    final text = controller.text;
    final selection = controller.selection;

    int start = selection.start;
    int end = selection.end;

    if (start < 0 || end < 0) {
      start = text.length;
      end = text.length;
    }

    final newText = text.replaceRange(start, end, symbol);
    final newSelectionIndex = start + symbol.length;

    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newSelectionIndex),
    );

    if (focusNode != null && !focusNode.hasFocus) {
      focusNode.requestFocus();
    }
  }
}

/// A compact, sleek symbol toolbar strip that sits directly above any input field.
class SymbolToolbarStrip extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final VoidCallback? onChanged;

  const SymbolToolbarStrip({
    super.key,
    required this.controller,
    this.focusNode,
    this.onChanged,
  });

  void _onSymbolTap(BuildContext context, String symbol) {
    MathSymbolsData.insertSymbol(controller, symbol, focusNode: focusNode);
    if (onChanged != null) onChanged!();
  }

  void _showFullPickerModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FullSymbolPickerModal(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;

    return Container(
      height: 40,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? const Color(0xFF334155)
              : const Color(0xFFCBD5E1),
        ),
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              Icons.functions_rounded,
              size: 16,
              color: Color(0xFF6366F1),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: MathSymbolsData.quickSymbols.map((symbol) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: InkWell(
                      onTap: () => _onSymbolTap(context, symbol),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF0F172A)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF475569)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Text(
                          symbol,
                          style: TextStyle(
                            color: context.textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: symbol.length > 3 ? 11 : 13,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => _showFullPickerModal(context),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.grid_view_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'More',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full Categorized Math Symbol Picker Modal Sheet.
class FullSymbolPickerModal extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final VoidCallback? onChanged;

  const FullSymbolPickerModal({
    super.key,
    required this.controller,
    this.focusNode,
    this.onChanged,
  });

  @override
  State<FullSymbolPickerModal> createState() => _FullSymbolPickerModalState();
}

class _FullSymbolPickerModalState extends State<FullSymbolPickerModal>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: MathSymbolsData.categories.length,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _insert(String symbol) {
    MathSymbolsData.insertSymbol(
      widget.controller,
      symbol,
      focusNode: widget.focusNode,
    );
    if (widget.onChanged != null) widget.onChanged!();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.55,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Modal Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                const Icon(
                  Icons.functions_rounded,
                  color: Color(0xFF6366F1),
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  'Math & Science Symbol Library',
                  style: TextStyle(
                    color: context.textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Tab Bar
          TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: const Color(0xFF6366F1),
            unselectedLabelColor: context.textColor60,
            indicatorColor: const Color(0xFF6366F1),
            tabs: MathSymbolsData.categories.map((cat) {
              return Tab(
                icon: Icon(cat.icon, size: 18),
                text: cat.title,
              );
            }).toList(),
          ),

          const Divider(height: 1),

          // Tab Body with Grids
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: MathSymbolsData.categories.map((cat) {
                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 75,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.2,
                  ),
                  itemCount: cat.symbols.length,
                  itemBuilder: (context, idx) {
                    final symbol = cat.symbols[idx];
                    return InkWell(
                      onTap: () => _insert(symbol),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E293B)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Text(
                          symbol,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: context.textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: symbol.length > 4 ? 11 : 14,
                          ),
                        ),
                      ),
                    );
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

/// A convenient wrapper that places a [SymbolToolbarStrip] directly above any child input field.
class SymbolInputFieldWrapper extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final Widget child;
  final VoidCallback? onChanged;

  /// When false, the inline [SymbolToolbarStrip] is not rendered — use this
  /// when a shared/global toolbar elsewhere handles symbol insertion instead.
  final bool showToolbar;

  /// Called whenever the wrapped [child] gains focus (including via a
  /// descendant, e.g. the actual editable text node inside a TextFormField),
  /// so a shared toolbar can track which field is currently active.
  final VoidCallback? onFocusGained;

  const SymbolInputFieldWrapper({
    super.key,
    required this.controller,
    required this.child,
    this.focusNode,
    this.onChanged,
    this.showToolbar = true,
    this.onFocusGained,
  });

  @override
  Widget build(BuildContext context) {
    final Widget focusAwareChild = Focus(
      onFocusChange: (hasFocus) {
        if (hasFocus) onFocusGained?.call();
      },
      child: child,
    );

    if (!showToolbar) {
      return focusAwareChild;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SymbolToolbarStrip(
          controller: controller,
          focusNode: focusNode,
          onChanged: onChanged,
        ),
        focusAwareChild,
      ],
    );
  }
}
