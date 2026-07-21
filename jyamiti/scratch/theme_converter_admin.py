import os
import re

admin_dir = r"c:\Users\USER\Desktop\myprojects\Jyamiti final\jyamiti\lib\presentation\features\admin"

replacements = [
    # Scaffold backgrounds & gradients
    (r'\[\s*Color\(0xFF0F172A\),\s*Color\(0xFF1E1B4B\),\s*Color\(0xFF0F172A\)\s*\]', 
     'context.isDark ? const [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF0F172A)] : const [Color(0xFFF1F5F9), Color(0xFFE2E8F0), Color(0xFFF1F5F9)]'),
    
    (r'\[\s*const\s*Color\(0xFF0F172A\),\s*const\s*Color\(0xFF1E1B4B\),\s*const\s*Color\(0xFF0F172A\)\s*\]', 
     'context.isDark ? const [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF0F172A)] : const [Color(0xFFF1F5F9), Color(0xFFE2E8F0), Color(0xFFF1F5F9)]'),

    # Dialog / Card backgrounds
    (r'backgroundColor:\s*const\s*Color\(0xFF0F172A\)\.withValues\(alpha:\s*0\.35\)', 
     'backgroundColor: context.isDark ? const Color(0xFF0F172A).withValues(alpha: 0.35) : Colors.white.withOpacity(0.95)'),
    (r'backgroundColor:\s*Color\(0xFF0F172A\)\.withValues\(alpha:\s*0\.35\)', 
     'backgroundColor: context.isDark ? const Color(0xFF0F172A).withValues(alpha: 0.35) : Colors.white.withOpacity(0.95)'),
    (r'backgroundColor:\s*const\s*Color\(0xFF1E293B\)', 'backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white'),
    (r'backgroundColor:\s*Color\(0xFF1E293B\)', 'backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white'),

    # Borders
    (r'BorderSide\(\s*color:\s*Colors\.white\.withValues\(alpha:\s*0\.2\)', 'BorderSide(color: context.glassBorder'),
    (r'BorderSide\(\s*color:\s*Colors\.white24\)', 'BorderSide(color: context.glassBorder)'),
    (r'BorderSide\(\s*color:\s*Colors\.white12\)', 'BorderSide(color: context.glassBorder)'),
    (r'color:\s*Colors\.white\.withValues\(alpha:\s*0\.1\)', 'color: context.glassBorder'),
    (r'color:\s*Colors\.white\.withValues\(alpha:\s*0\.05\)', 'color: context.glassBorder'),
    (r'color:\s*Colors\.white10', 'color: context.glassBorder'),
    (r'color:\s*Colors\.white24', 'color: context.glassBorder'),

    # TabBar label colors
    (r'labelColor:\s*Colors\.white', 'labelColor: context.textColor'),
    (r'unselectedLabelColor:\s*Colors\.white60', 'unselectedLabelColor: context.textColor60'),
    (r'unselectedLabelColor:\s*Colors\.white70', 'unselectedLabelColor: context.textColor70'),

    # Direct Colors.white in TextStyle (excluding button labels)
    (r"style:\s*const\s*TextStyle\(\s*color:\s*Colors\.white,\s*fontSize:\s*(\d+),\s*fontWeight:\s*FontWeight\.bold,\s*\)", r"style: TextStyle(color: context.textColor, fontSize: \1, fontWeight: FontWeight.bold)"),
    (r"style:\s*TextStyle\(\s*color:\s*Colors\.white,\s*fontSize:\s*(\d+),\s*fontWeight:\s*FontWeight\.bold,\s*\)", r"style: TextStyle(color: context.textColor, fontSize: \1, fontWeight: FontWeight.bold)"),
    (r"style:\s*const\s*TextStyle\(\s*color:\s*Colors\.white\s*\)", "style: TextStyle(color: context.textColor)"),
    (r"style:\s*TextStyle\(\s*color:\s*Colors\.white\s*\)", "style: TextStyle(color: context.textColor)"),
    (r"style:\s*const\s*TextStyle\(\s*color:\s*Colors\.white70\s*\)", "style: TextStyle(color: context.textColor70)"),
    (r"style:\s*TextStyle\(\s*color:\s*Colors\.white70\s*\)", "style: TextStyle(color: context.textColor70)"),
    (r"style:\s*const\s*TextStyle\(\s*color:\s*Colors\.white60\s*\)", "style: TextStyle(color: context.textColor60)"),
    (r"style:\s*TextStyle\(\s*color:\s*Colors\.white60\s*\)", "style: TextStyle(color: context.textColor60)"),
    (r"style:\s*const\s*TextStyle\(\s*color:\s*Colors\.white54\s*\)", "style: TextStyle(color: context.textColor54)"),
    (r"style:\s*TextStyle\(\s*color:\s*Colors\.white54\s*\)", "style: TextStyle(color: context.textColor54)"),
    (r"style:\s*const\s*TextStyle\(\s*color:\s*Colors\.white30\s*\)", "style: TextStyle(color: context.textColor54.withValues(alpha: 0.5))"),
    (r"style:\s*TextStyle\(\s*color:\s*Colors\.white30\s*\)", "style: TextStyle(color: context.textColor54.withValues(alpha: 0.5))"),

    # Direct color parameters
    (r'color:\s*Colors\.white70', 'color: context.textColor70'),
    (r'color:\s*Colors\.white60', 'color: context.textColor60'),
    (r'color:\s*Colors\.white54', 'color: context.textColor54'),
    (r'color:\s*Colors\.white30', 'color: context.textColor54.withValues(alpha: 0.5)'),
    (r'color:\s*Colors\.white24', 'color: context.textColor54.withValues(alpha: 0.4)'),
]

for root, dirs, files in os.walk(admin_dir):
    for file in files:
        if file.endswith(".dart"):
            path = os.path.join(root, file)
            with open(path, 'r', encoding='utf-8') as f:
                content = f.read()
                
            # Check if we need to add the import header
            if "theme_provider.dart" not in content:
                content = re.sub(
                    r"import 'package:flutter/material.dart';",
                    "import 'package:flutter/material.dart';\nimport 'package:jyamiti/providers/theme_provider.dart';",
                    content
                )
                
            new_content = content
            for pattern, replacement in replacements:
                new_content = re.sub(pattern, replacement, new_content)
                
            # Clean up const violations
            new_content = re.sub(r'const\s+BorderSide\(\s*color:\s*context', 'BorderSide(color: context', new_content)
            new_content = re.sub(r'const\s+OutlineInputBorder\(\s*borderSide:\s*BorderSide\(\s*color:\s*context', 'OutlineInputBorder(borderSide: BorderSide(color: context', new_content)
            new_content = re.sub(r'const\s+TextStyle\(\s*color:\s*context', 'TextStyle(color: context', new_content)
            new_content = re.sub(r'const\s+IconThemeData\(\s*color:\s*context', 'IconThemeData(color: context', new_content)
            new_content = re.sub(r'const\s+Border\(\s*bottom:\s*BorderSide\(\s*color:\s*context', 'Border(bottom: BorderSide(color: context', new_content)
            new_content = re.sub(r'const\s+Border\(\s*bottom:\s*BorderSide\(\s*color:\s*const\s*Color', 'Border(bottom: BorderSide(color: const Color', new_content)
            new_content = re.sub(r'const\s+Divider\(\s*color:\s*context', 'Divider(color: context', new_content)
            new_content = re.sub(r'const\s+EdgeInsets', 'EdgeInsets', new_content) # safety for mixed const elements
            
            with open(path, 'w', encoding='utf-8') as f:
                f.write(new_content)
            print(f"Theme-converted: {file}")

print("Admin directory theme conversion completed successfully!")
