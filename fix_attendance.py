import re

file_path = 'frontend/lib/presentation/features/dashboard/screens/student_detailed_attendance_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

if "import 'package:provider/provider.dart';" not in content:
    content = content.replace("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport 'package:provider/provider.dart';")

content = re.sub(r'Widget _buildSummaryCard\((.*?)\)\s*\{', r'Widget _buildSummaryCard(\1, BuildContext context) {', content)
content = re.sub(r'Widget _buildRecentAttendanceList\((.*?)\)\s*\{', r'Widget _buildRecentAttendanceList(\1, BuildContext context) {', content)
content = re.sub(r'Widget _buildMonthlyTrendChart\((.*?)\)\s*\{', r'Widget _buildMonthlyTrendChart(\1, BuildContext context) {', content)

# update calls
content = re.sub(r'_buildSummaryCard\(([^,]+)\)', r'_buildSummaryCard(\1, context)', content)
content = re.sub(r'_buildRecentAttendanceList\(([^,]+)\)', r'_buildRecentAttendanceList(\1, context)', content)
content = re.sub(r'_buildMonthlyTrendChart\(([^,]+)\)', r'_buildMonthlyTrendChart(\1, context)', content)

# Since we replaced context.context in some cases, let's just make sure we didn't add duplicate context
content = content.replace('context, context', 'context')

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Fixed detailed attendance screen")
