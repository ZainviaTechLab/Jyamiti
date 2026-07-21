import os
import re

files = [
    'frontend/lib/presentation/features/dashboard/screens/student_payments_screen.dart',
    'frontend/lib/presentation/features/dashboard/screens/student_performance_screen.dart',
    'frontend/lib/presentation/features/academic/screens/schedules_screen.dart'
]

theme_vars = """    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? Colors.white70 : const Color(0xFF475569);
    final textFaint = isDark ? Colors.white54 : const Color(0xFF94A3B8);
    final glassBg = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03);
    final glassBorder = isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05);
"""

theme_vars_no_context = """    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? Colors.white70 : const Color(0xFF475569);
    final textFaint = isDark ? Colors.white54 : const Color(0xFF94A3B8);
    final glassBg = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03);
    final glassBorder = isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05);
"""

for filepath in files:
    if not os.path.exists(filepath):
        print(f"Not found: {filepath}")
        continue
        
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
        
    # Add imports if not there
    if 'theme_provider.dart' not in content:
        content = content.replace("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport 'package:provider/provider.dart';\nimport '../../../../providers/theme_provider.dart';")
        
    # Inject into build method
    content = re.sub(r'(Widget build\(BuildContext context\)\s*\{)', r'\1\n' + theme_vars, content)
    
    # Inject into _build methods
    # e.g. Widget _buildUpToDateCard() {
    content = re.sub(r'(Widget _build[A-Za-z0-9_]+\([^\)]*\)\s*\{)', r'\1\n' + theme_vars_no_context, content)
    
    # Gradients
    content = content.replace("colors: [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF0F172A)]", "colors: isDark ? const [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF0F172A)] : const [Color(0xFFF1F5F9), Color(0xFFE2E8F0), Color(0xFFF1F5F9)]")
    content = content.replace("colors: const [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF0F172A)]", "colors: isDark ? const [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF0F172A)] : const [Color(0xFFF1F5F9), Color(0xFFE2E8F0), Color(0xFFF1F5F9)]")
    
    # Colors replace
    content = content.replace("color: Colors.white.withOpacity(0.03)", "color: glassBg")
    content = content.replace("color: Colors.white.withOpacity(0.05)", "color: glassBg")
    content = content.replace("color: Colors.white.withOpacity(0.08)", "color: glassBorder")
    content = content.replace("color: Colors.white.withOpacity(0.1)", "color: glassBorder")
    
    # We replace text colors but carefully so we don't mess up existing usages
    # e.g., style: const TextStyle(color: Colors.white) -> style: TextStyle(color: textColor)
    # we have to remove "const" if it is there before TextStyle.
    content = re.sub(r'const TextStyle\(([^)]*)color:\s*Colors\.white([^)]*)\)', r'TextStyle(\1color: textColor\2)', content)
    content = re.sub(r'const TextStyle\(([^)]*)color:\s*Colors\.white70([^)]*)\)', r'TextStyle(\1color: textMuted\2)', content)
    content = re.sub(r'const TextStyle\(([^)]*)color:\s*Colors\.white54([^)]*)\)', r'TextStyle(\1color: textFaint\2)', content)
    
    content = re.sub(r'TextStyle\(([^)]*)color:\s*Colors\.white([^)]*)\)', r'TextStyle(\1color: textColor\2)', content)
    content = re.sub(r'TextStyle\(([^)]*)color:\s*Colors\.white70([^)]*)\)', r'TextStyle(\1color: textMuted\2)', content)
    content = re.sub(r'TextStyle\(([^)]*)color:\s*Colors\.white54([^)]*)\)', r'TextStyle(\1color: textFaint\2)', content)
    
    content = content.replace("color: Colors.white,", "color: textColor,")
    content = content.replace("color: Colors.white70", "color: textMuted")
    content = content.replace("color: Colors.white54", "color: textFaint")
    
    # For Container color: Color(0xFF0F172A).withOpacity(0.6)
    content = content.replace("color: const Color(0xFF0F172A).withOpacity(0.6)", "color: isDark ? const Color(0xFF0F172A).withOpacity(0.6) : Colors.white.withOpacity(0.6)")
    
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
        
    print(f"Refactored {filepath}")
