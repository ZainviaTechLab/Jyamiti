import os
import re

dir_path_academic = r"c:\Users\USER\Desktop\myprojects\Jyamiti final\jyamiti\lib\presentation\features\academic\screens"
dir_path_admin = r"c:\Users\USER\Desktop\myprojects\Jyamiti final\jyamiti\lib\presentation\features\admin\screens"
dir_path_chat = r"c:\Users\USER\Desktop\myprojects\Jyamiti final\jyamiti\lib\presentation\features\chat\screens"

files = [
    # Academic screens
    (dir_path_academic, "video_player_screen.dart"),
    (dir_path_academic, "worksheet_submissions_screen.dart"),
    (dir_path_academic, "tutor_tutorials_screen.dart"),
    (dir_path_academic, "student_tutorials_screen.dart"),
    (dir_path_academic, "session_notes_screen.dart"),
    (dir_path_academic, "schedules_screen.dart"),
    (dir_path_academic, "note_submissions_screen.dart"),
    (dir_path_academic, "pdf_annotation_screen.dart"),
    (dir_path_academic, "file_viewer_screen.dart"),
    (dir_path_academic, "batch_notes_screen.dart"),
    (dir_path_academic, "batch_worksheets_screen.dart"),
    # Admin screens
    (dir_path_admin, "course_syllabus_screen.dart"),
    (dir_path_admin, "admin_console_screen.dart"),
    (dir_path_admin, "admin_batch_detail_screen.dart"),
    # Chat screens
    (dir_path_chat, "chat_list_screen.dart"),
    (dir_path_chat, "chat_detail_screen.dart")
]

replacements = [
    # Scaffold background
    (r'backgroundColor:\s*const\s*Color\(0xFF0F172A\)', 'backgroundColor: context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9)'),
    (r'backgroundColor:\s*Color\(0xFF0F172A\)', 'backgroundColor: context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9)'),

    # AppBar background
    (r'backgroundColor:\s*const\s*Color\(0xFF1E293B\)', 'backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white'),
    (r'backgroundColor:\s*Color\(0xFF1E293B\)', 'backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white'),

    # Dialog background
    (r'backgroundColor:\s*const\s*Color\(0xFF1E293B\)', 'backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white'),

    # Text styles
    (r'const\s+TextStyle\(\s*color:\s*Colors\.white\s*\)', 'TextStyle(color: context.textColor)'),
    (r'const\s+TextStyle\(\s*color:\s*Colors\.white,\s*', 'TextStyle(color: context.textColor, '),
    (r'TextStyle\(\s*color:\s*Colors\.white\s*\)', 'TextStyle(color: context.textColor)'),
    (r'TextStyle\(\s*color:\s*Colors\.white,\s*', 'TextStyle(color: context.textColor, '),

    (r'const\s+TextStyle\(\s*color:\s*Colors\.white70\s*\)', 'TextStyle(color: context.textColor70)'),
    (r'const\s+TextStyle\(\s*color:\s*Colors\.white70,\s*', 'TextStyle(color: context.textColor70, '),
    (r'TextStyle\(\s*color:\s*Colors\.white70\s*\)', 'TextStyle(color: context.textColor70)'),
    (r'TextStyle\(\s*color:\s*Colors\.white70,\s*', 'TextStyle(color: context.textColor70, '),

    (r'const\s+TextStyle\(\s*color:\s*Colors\.white60\s*\)', 'TextStyle(color: context.textColor60)'),
    (r'const\s+TextStyle\(\s*color:\s*Colors\.white60,\s*', 'TextStyle(color: context.textColor60, '),
    (r'TextStyle\(\s*color:\s*Colors\.white60\s*\)', 'TextStyle(color: context.textColor60)'),
    (r'TextStyle\(\s*color:\s*Colors\.white60,\s*', 'TextStyle(color: context.textColor60, '),

    (r'const\s+TextStyle\(\s*color:\s*Colors\.white54\s*\)', 'TextStyle(color: context.textColor54)'),
    (r'const\s+TextStyle\(\s*color:\s*Colors\.white54,\s*', 'TextStyle(color: context.textColor54, '),
    (r'TextStyle\(\s*color:\s*Colors\.white54\s*\)', 'TextStyle(color: context.textColor54)'),
    (r'TextStyle\(\s*color:\s*Colors\.white54,\s*', 'TextStyle(color: context.textColor54, '),

    # Direct color parameters
    (r'color:\s*Colors\.white70', 'color: context.textColor70'),
    (r'color:\s*Colors\.white60', 'color: context.textColor60'),
    (r'color:\s*Colors\.white54', 'color: context.textColor54'),
    (r'color:\s*Colors\.white30', 'color: context.textColor54.withOpacity(0.5)'),
    (r'color:\s*Colors\.white24', 'color: context.textColor54.withOpacity(0.4)'),
    (r'color:\s*Colors\.white12', 'color: context.glassBorder'),
    (r'color:\s*Colors\.white\s*,', 'color: context.textColor,'),
    (r'color:\s*Colors\.white\s*\)', 'color: context.textColor)'),

    # Opacities & transparents
    (r'Colors\.white\.withOpacity\(0\.01\)', 'context.glassBg'),
    (r'Colors\.white\.withOpacity\(0\.02\)', 'context.glassBg'),
    (r'Colors\.white\.withOpacity\(0\.03\)', 'context.glassBg'),
    (r'Colors\.white\.withOpacity\(0\.04\)', 'context.glassBg'),
    (r'Colors\.white\.withOpacity\(0\.05\)', 'context.glassBg'),
    (r'Colors\.white\.withOpacity\(0\.06\)', 'context.glassBorder'),
    (r'Colors\.white\.withOpacity\(0\.08\)', 'context.glassBorder'),
    (r'Colors\.white\.withOpacity\(0\.1\)', 'context.glassBorder'),
    (r'Colors\.white\.withOpacity\(0\.12\)', 'context.glassBorder'),
    (r'Colors\.white\.withOpacity\(0\.15\)', 'context.glassBorder'),
    (r'Colors\.white10', 'context.glassBorder'),
    (r'Colors\.white24', 'context.glassBorder'),

    # Dropdowns & Inputs fillColors
    (r"dropdownColor:\s*const\s*Color\(0xFF1E1B4B\)", "dropdownColor: context.isDark ? const Color(0xFF1E1B4B) : Colors.white"),
    (r"dropdownColor:\s*const\s*Color\(0xFF1E293B\)", "dropdownColor: context.isDark ? const Color(0xFF1E293B) : Colors.white"),
    (r"fillColor:\s*const\s*Color\(0xFF1E1B4B\)", "fillColor: context.isDark ? const Color(0xFF1E1B4B) : Colors.white"),
    (r"fillColor:\s*const\s*Color\(0xFF1E293B\)", "fillColor: context.isDark ? const Color(0xFF1E293B) : Colors.white"),
    (r"fillColor:\s*Color\(0xFF1E1B4B\)", "fillColor: context.isDark ? const Color(0xFF1E1B4B) : Colors.white"),
    (r"fillColor:\s*Color\(0xFF1E293B\)", "fillColor: context.isDark ? const Color(0xFF1E293B) : Colors.white"),
    (r"fillColor:\s*const\s*Color\(0xFF0F172A\)", "fillColor: context.isDark ? const Color(0xFF0F172A) : Colors.white"),
    (r"fillColor:\s*Color\(0xFF0F172A\)", "fillColor: context.isDark ? const Color(0xFF0F172A) : Colors.white"),
    
    (r"color:\s*const\s*Color\(0xFF1E293B\)", "color: context.isDark ? const Color(0xFF1E293B) : Colors.white"),
    (r"color:\s*Color\(0xFF1E293B\)", "color: context.isDark ? const Color(0xFF1E293B) : Colors.white"),
    (r"color:\s*const\s*Color\(0xFF0F172A\)", "color: context.isDark ? const Color(0xFF0F172A) : Colors.white"),
    (r"color:\s*Color\(0xFF0F172A\)", "color: context.isDark ? const Color(0xFF0F172A) : Colors.white"),
]

for dir_path, filename in files:
    filepath = os.path.join(dir_path, filename)
    if not os.path.exists(filepath):
        print(f"File not found: {filename}")
        continue
        
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
        
    # Check if we need to add the import header
    if "theme_provider.dart" not in content:
        content = content.replace(
            "import 'package:flutter/material.dart';",
            "import 'package:flutter/material.dart';\nimport 'package:jyamiti/providers/theme_provider.dart';"
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
    new_content = re.sub(r'const\s+Divider\(\s*color:\s*context', 'Divider(color: context', new_content)

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(new_content)
    print(f"Processed: {filename}")
