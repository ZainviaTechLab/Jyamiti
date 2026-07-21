import os
import re

files = [
    'frontend/lib/presentation/features/academic/screens/schedules_screen.dart',
    'frontend/lib/presentation/features/dashboard/screens/student_dashboard.dart',
    'frontend/lib/presentation/features/dashboard/screens/student_detailed_attendance_screen.dart',
    'frontend/lib/presentation/features/dashboard/screens/student_payments_screen.dart',
    'frontend/lib/presentation/features/dashboard/screens/student_performance_screen.dart',
    'frontend/lib/presentation/features/dashboard/screens/student_settings_screen.dart'
]

remove_block1 = """    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? Colors.white70 : const Color(0xFF475569);
    final textFaint = isDark ? Colors.white54 : const Color(0xFF94A3B8);
    final glassBg = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03);
    final glassBorder = isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05);

"""

remove_block2 = """    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? Colors.white70 : const Color(0xFF475569);
    final textFaint = isDark ? Colors.white54 : const Color(0xFF94A3B8);
    final glassBg = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03);
    final glassBorder = isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05);
"""

for filepath in files:
    if not os.path.exists(filepath): continue
    
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Ensure import is present for the extension
    if "import '../../../../providers/theme_provider.dart';" not in content:
        content = content.replace("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport '../../../../providers/theme_provider.dart';")
    
    # Remove the boilerplate injected previously
    content = content.replace(remove_block1, '')
    content = content.replace(remove_block2, '')
    
    # We also have to handle any manual boilerplate from the user like:
    user_boilerplate = """    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? Colors.white70 : const Color(0xFF475569);
    final textFaint = isDark ? Colors.white54 : const Color(0xFF94A3B8);
    final glassBg = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03);
    final glassBorder = isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05);"""
    content = content.replace(user_boilerplate, '')
    
    # Now replace the variables with context.var
    # using negative lookbehind to avoid context.context.var
    variables = ['isDark', 'textColor70', 'textColor60', 'textColor54', 'textColor', 'textMuted', 'textFaint', 'glassBg', 'glassBorder']
    for var in variables:
        content = re.sub(r'(?<!context\.)\b' + var + r'\b', f'context.{var}', content)
        
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
        
    print(f"Fixed {filepath}")
